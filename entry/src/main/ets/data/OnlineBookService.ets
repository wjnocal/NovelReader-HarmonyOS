import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BookRecord, ChapterRecord, OnlineBookResult, OnlineExtractionRule, OnlineSourceInfo } from '../model/Models';
import { ErrorText } from './ErrorText';
import { LibraryStore } from './LibraryStore';
import { OnlineRuleAdapter } from './OnlineRuleAdapter';
import { OnlineBookExporter } from './OnlineBookExporter';
import { OnlineChapterCache } from './OnlineChapterCache';
import { OnlineChapterPublisher, OnlineDownloadState } from './OnlineDownloadState';
import { HtmlNode, SimpleHtml } from './SimpleHtml';

class SourceSearchData {
  name: string = '';
  s: string = '';
  searchkey: string = '';
  searchtype: string = '';
  Submit: string = '';
  type: string = '';
}

class SourceSearchRule {
  url: string = '';
  method: string = 'get';
  data: SourceSearchData = new SourceSearchData();
  result: string = '';
  bookName: string = '';
  author: string = '';
  category: string = '';
  latestChapter: string = '';
  lastUpdateTime: string = '';
  status: string = '';
  nextPage: string = '';
  disabled: boolean = false;
  cookies: string = '';
  minIntervalMillis: number = 0;
}

class SourceBookRule {
  url: string = '';
  bookName: string = '';
  author: string = '';
  category: string = '';
  intro: string = '';
}

class SourceTocRule {
  url: string = '';
  baseUri: string = '';
  item: string = '';
  nextPage: string = '';
  isDesc: boolean = false;
}

class SourceChapterRule {
  title: string = '';
  content: string = '';
  filterTxt: string = '';
  filterTag: string = '';
  nextPage: string = '';
  nextPageInJs: string = '';
  nextChapterLink: string = '';
}

class SourceCrawlRule {
  timeoutMillis: number = 15000;
  minIntervalMillis: number = 0;
  maxIntervalMillis: number = 0;
  maxRetries: number = 2;
  concurrency: number = 1;
}

class OnlineSource {
  id: string = '';
  name: string = '';
  baseUrl: string = '';
  enabled: boolean = true;
  needProxy: boolean = false;
  comment: string = '';
  search: SourceSearchRule = new SourceSearchRule();
  book: SourceBookRule = new SourceBookRule();
  toc: SourceTocRule = new SourceTocRule();
  chapter: SourceChapterRule = new SourceChapterRule();
  crawl: SourceCrawlRule = new SourceCrawlRule();
}

class ChapterReference {
  title: string = '';
  url: string = '';
}

export type OnlineProgress = (message: string, completed?: number, total?: number) => void;
export type OnlineSearchResults = (results: Array<OnlineBookResult>) => void;

export class OnlineSearchOptions {
  requestTimeoutMillis: number = 8000;
  sourceTimeoutMillis: number = 20000;
  totalTimeoutMillis: number = 60000;
}

export class OnlineHttpError extends Error {
  retryable: boolean;
  constructor(message: string, retryable: boolean) {
    super(message);
    this.retryable = retryable;
  }
}

export class OnlineDownloadCancelToken {
  cancelled: boolean = false;
  reason: string;
  private callbacks: Set<() => void> = new Set<() => void>();

  constructor(reason: string = '下载已取消') {
    this.reason = reason;
  }

  cancel(reason: string = ''): void {
    if (this.cancelled) return;
    if (reason.length > 0) this.reason = reason;
    this.cancelled = true;
    this.callbacks.forEach((callback: () => void): void => callback());
    this.callbacks.clear();
  }

  register(callback: () => void): void {
    if (this.cancelled) callback();
    else this.callbacks.add(callback);
  }

  unregister(callback: () => void): void {
    this.callbacks.delete(callback);
  }

  throwIfCancelled(): void {
    if (this.cancelled) {
      throw new Error(this.reason);
    }
  }
}

export class OnlineBookService {
  private context: common.UIAbilityContext;
  private sources: Array<OnlineSource> = new Array<OnlineSource>();
  private searchOptions: OnlineSearchOptions;
  private static nextRequestAt: Map<string, number> = new Map<string, number>();
  private static backoffUntil: Map<string, number> = new Map<string, number>();

  constructor(context: common.UIAbilityContext, searchOptions: OnlineSearchOptions = new OnlineSearchOptions()) {
    this.context = context;
    this.searchOptions = searchOptions;
  }

  async getSources(): Promise<Array<OnlineSourceInfo>> {
    await this.ensureSources();
    return this.sources.map((source: OnlineSource): OnlineSourceInfo => {
      const info = new OnlineSourceInfo();
      info.id = source.id;
      info.name = source.name;
      info.baseUrl = source.baseUrl;
      info.enabled = source.enabled;
      info.searchable = !source.search.disabled && source.search.url.length > 0 && source.search.result.length > 0;
      info.needProxy = source.needProxy;
      info.comment = source.comment;
      info.concurrency = source.crawl.concurrency;
      return info;
    });
  }

  async getExtractionRule(url: string): Promise<OnlineExtractionRule> {
    await this.ensureSources();
    const source = this.sources.find((item: OnlineSource): boolean => item.enabled && this.sameHost(url, item.baseUrl));
    const rule = new OnlineExtractionRule();
    if (source === undefined) {
      return rule;
    }
    rule.sourceId = source.id;
    rule.sourceName = source.name;
    rule.titleSelector = this.plainSelector(source.chapter.title);
    rule.contentSelector = this.plainSelector(source.chapter.content);
    rule.filterPattern = source.chapter.filterTxt;
    rule.nextPageSelector = this.plainSelector(source.chapter.nextPage);
    rule.nextChapterPattern = source.chapter.nextChapterLink;
    return rule;
  }

  async searchSelected(keyword: string, sourceIds: Array<string>,
    progress?: OnlineProgress, cancelToken: OnlineDownloadCancelToken = new OnlineDownloadCancelToken('搜索已取消'),
    onResults?: OnlineSearchResults): Promise<Array<OnlineBookResult>> {
    await this.ensureSources();
    const selected = new Set<string>(sourceIds);
    return this.searchInternal(keyword, selected, progress, cancelToken, onResults);
  }

  async search(keyword: string, progress?: OnlineProgress,
    cancelToken: OnlineDownloadCancelToken = new OnlineDownloadCancelToken('搜索已取消'),
    onResults?: OnlineSearchResults): Promise<Array<OnlineBookResult>> {
    await this.ensureSources();
    return this.searchInternal(keyword, undefined, progress, cancelToken, onResults);
  }

  async resultForUrl(url: string, sourceIds: Array<string>): Promise<OnlineBookResult> {
    await this.ensureSources();
    const selected = new Set<string>(sourceIds);
    const source = this.sources.find((item: OnlineSource): boolean => item.enabled && selected.has(item.id) &&
      this.sameHost(url, item.baseUrl));
    if (source === undefined) {
      throw new Error('所选书源中没有与该网址匹配的站点');
    }
    const result = new OnlineBookResult();
    result.sourceId = source.id;
    result.sourceName = source.name;
    result.bookName = '网址下载';
    result.url = url;
    return result;
  }

  private async searchInternal(keyword: string, selected: Set<string> | undefined,
    progress: OnlineProgress | undefined, cancelToken: OnlineDownloadCancelToken,
    onResults: OnlineSearchResults | undefined): Promise<Array<OnlineBookResult>> {
    cancelToken.throwIfCancelled();
    const enabled = this.sources.filter((source: OnlineSource): boolean => source.enabled &&
      (selected === undefined || selected.has(source.id)) && !source.search.disabled &&
      source.search.url.length > 0 && source.search.result.length > 0);
    let failedSources = 0;
    let completedSources = 0;
    let timedOut = false;
    const active = new Set<string>();
    const failures = new Array<string>();
    const bySource = new Array<Array<OnlineBookResult>>(enabled.length);
    const session = new OnlineDownloadCancelToken('搜索已取消');
    const abort = (): void => session.cancel(cancelToken.reason);
    cancelToken.register(abort);
    const timeout = setTimeout((): void => {
      timedOut = true;
      session.cancel('本轮搜索超时，已停止等待');
    }, Math.max(1, this.searchOptions.totalTimeoutMillis));
    const report = (detail: string = ''): void => {
      if (progress === undefined) return;
      const searching = active.size > 0 ? `，正在搜索：${Array.from(active).join('、')}` : '';
      const failure = detail.length > 0 ? `；${detail}` : '';
      progress(`搜索进度 ${completedSources}/${enabled.length}${searching}${failure}`, completedSources, enabled.length);
    };
    const publish = (): void => {
      if (onResults !== undefined) onResults(this.mergeSearchResults(bySource));
    };
    let cursor = 0;
    const worker = async (): Promise<void> => {
      while (cursor < enabled.length && !session.cancelled) {
        const index = cursor++;
        const source = enabled[index];
        const sourceToken = new OnlineDownloadCancelToken('搜索已取消');
        const abortSource = (): void => sourceToken.cancel(session.reason);
        session.register(abortSource);
        const sourceTimeout = setTimeout((): void => {
          sourceToken.cancel('书源搜索超时，已跳过');
        }, Math.max(1, this.searchOptions.sourceTimeoutMillis));
        active.add(source.name);
        report();
        let detail = '';
        try {
          bySource[index] = await this.searchSource(source, keyword, sourceToken,
            (results: Array<OnlineBookResult>): void => {
              if (session.cancelled) return;
              bySource[index] = results;
              publish();
              report(`${source.name} 已找到 ${results.length} 个结果`);
            });
        } catch (error) {
          failedSources++;
          detail = `${source.name} 已跳过：${ErrorText.from(error as BusinessError)}`;
          failures.push(detail);
        } finally {
          clearTimeout(sourceTimeout);
          session.unregister(abortSource);
          active.delete(source.name);
          completedSources++;
          publish();
          report(detail);
        }
      }
    };
    try {
      const workers = new Array<Promise<void>>();
      for (let index = 0; index < Math.min(4, enabled.length); index++) workers.push(worker());
      await Promise.all(workers);
    } finally {
      clearTimeout(timeout);
      cancelToken.unregister(abort);
    }
    cancelToken.throwIfCancelled();
    const output = this.mergeSearchResults(bySource);
    const failed = failures.length > 0 ? `；${failures.join('；')}` : '';
    const deadline = timedOut ? '搜索达到时间上限，保留已找到的结果' : '搜索完成';
    if (progress !== undefined) {
      progress(`${deadline}：${completedSources}/${enabled.length} 个书源已结束，找到 ${output.length} 个结果${failed}`,
        completedSources, enabled.length);
    }
    if (output.length === 0 && enabled.length > 0) {
      if (timedOut) throw new Error(`搜索超时，未找到结果，请减少所选书源或稍后重试${failed}`);
      if (failedSources === enabled.length) {
        throw new Error(`全部 ${enabled.length} 个书源搜索失败${failed}`);
      }
      const connected = enabled.length - failedSources;
      throw new Error(`已连接 ${connected} 个书源，但没有解析到匹配结果；书源页面可能已改版${failed}`);
    }
    return output;
  }

  private mergeSearchResults(bySource: Array<Array<OnlineBookResult>>): Array<OnlineBookResult> {
    const output = new Array<OnlineBookResult>();
    const seen = new Set<string>();
    bySource.forEach((results: Array<OnlineBookResult>): void => {
      results?.forEach((item: OnlineBookResult): void => {
        const key = `${item.sourceId}|${item.url}`;
        if (!seen.has(key)) {
          seen.add(key);
          output.push(item);
        }
      });
    });
    return output;
  }

  async downloadToLibrary(result: OnlineBookResult, format: string = 'txt', progress?: OnlineProgress,
    cancelToken: OnlineDownloadCancelToken = new OnlineDownloadCancelToken(),
    onReadable?: (book: BookRecord) => void): Promise<BookRecord> {
    await this.ensureSources();
    const source = this.sources.find((item: OnlineSource): boolean => item.id === result.sourceId);
    if (source === undefined) {
      throw new Error('书源已不存在，请重新搜索');
    }
    cancelToken.throwIfCancelled();
    progress?.('正在读取书籍信息', 0, 0);
    const bookDocument = await this.requestDocument(result.url, source, '', false, cancelToken);
    const resultTitle = result.bookName === '网址下载' ? this.genericBookTitle(bookDocument) : result.bookName;
    const title = this.fallback(this.selectValue(bookDocument, source.book.bookName, true), resultTitle);
    const resultAuthor = result.author.length > 0 ? result.author : this.genericBookAuthor(bookDocument);
    const author = this.cleanAuthor(this.fallback(this.selectValue(bookDocument, source.book.author, true), resultAuthor));
    const category = this.fallback(this.selectValue(bookDocument, source.book.category, true), result.category);
    const description = this.selectValue(bookDocument, source.book.intro, true);
    progress?.('正在读取章节目录', 0, 0);
    const references = await this.parseToc(source, result.url, bookDocument, cancelToken);
    if (references.length === 0) {
      throw new Error('书源没有返回章节目录');
    }

    const normalizedFormat = format.toLowerCase() === 'epub' ? 'epub' : 'txt';
    const identity = JSON.stringify([source.id, result.url, normalizedFormat, source.chapter,
      references.map((reference: ChapterReference): string => `${reference.url}|${reference.title}`)]);
    const downloadKey = OnlineDownloadState.key(identity);
    const snapshot = LibraryStore.load(this.context);
    const existing = snapshot.books.find((book: BookRecord): boolean => book.downloadKey === downloadKey) ??
      snapshot.books.find((book: BookRecord): boolean =>
      book.title.trim().toLowerCase() === title.trim().toLowerCase() &&
      book.author.trim().toLowerCase() === author.trim().toLowerCase());
    const now = Date.now();
    const id = existing === undefined ? `${now}_online` : existing.id;
    const directory = LibraryStore.bookDirectory(this.context, id);
    const chapterPath = existing === undefined || existing.chapterFilePath.length === 0 ?
      `${directory}/chapters.json` : existing.chapterFilePath;
    const book = existing === undefined ? new BookRecord() : existing;
    book.id = id;
    if (book.syncId.length === 0) book.syncId = `online-${id}`;
    book.title = title.length > 0 ? title : result.bookName;
    book.author = author.length > 0 ? author : '未知作者';
    book.category = category.length > 0 ? category : '网络小说';
    book.description = description;
    book.fileType = normalizedFormat;
    book.chapterFilePath = chapterPath;
    book.totalChapters = references.length;
    book.createdAt = book.createdAt > 0 ? book.createdAt : now;
    book.updatedAt = now;
    book.syncUpdatedAt = now;
    book.syncContentHash = '';
    // Existing complete books stay intact until their replacement finishes.
    const incremental = existing === undefined || !existing.downloadComplete;
    if (existing !== undefined && !existing.downloadComplete && existing.downloadKey !== downloadKey) {
      throw new Error('书源、下载格式、目录或解析规则已变化，请选择原书源与格式，或删除未完成书籍后重新下载');
    }
    const resumed = existing !== undefined && !existing.downloadComplete ? LibraryStore.loadChapters(existing) : [];
    let lastPublished = 0;
    let published = existing !== undefined;
    const publish = (chapters: Array<ChapterRecord>, complete: boolean = false, originalPath: string = ''): BookRecord => {
      const latest = LibraryStore.load(this.context);
      let target = latest.books.find((item: BookRecord): boolean => item.id === id);
      if (target === undefined && published) throw new Error('书籍已从书架移除，停止下载');
      if (target === undefined) {
        target = book;
        latest.books.push(target);
      }
      LibraryStore.saveChapters(chapterPath, chapters);
      target.chapterFilePath = chapterPath;
      if (target.syncId.length === 0) target.syncId = `online-${id}`;
      target.totalChapters = references.length;
      target.availableChapters = chapters.length;
      target.downloadKey = downloadKey;
      target.downloadComplete = complete;
      target.downloadRevision = (target.downloadRevision ?? 0) + 1;
      target.fileType = normalizedFormat;
      target.originalFilePath = originalPath;
      target.syncContentHash = '';
      target.syncUpdatedAt = Date.now();
      target.currentChapterIndex = Math.min(target.currentChapterIndex, chapters.length - 1);
      LibraryStore.save(this.context, latest);
      published = true;
      lastPublished = Date.now();
      onReadable?.(target);
      AppStorage.setOrCreate<number>('onlineLibraryRevision',
        (AppStorage.get<number>('onlineLibraryRevision') ?? 0) + 1);
      return target;
    };
    const cache = new OnlineChapterCache(this.context);
    const publisher = new OnlineChapterPublisher();
    resumed.forEach((chapter: ChapterRecord, index: number): void => {
      publisher.complete(index, chapter);
    });
    if (resumed.length > 0) onReadable?.(book);
    let chapters = new Array<ChapterRecord>();
    try {
      chapters = await this.downloadChapters(source, references, progress, cancelToken, cache, resumed,
        (index: number, chapter: ChapterRecord): void => {
          const appended = publisher.complete(index, chapter);
          if (incremental && appended.length > 0 &&
            (!published || Date.now() - lastPublished >= 750)) publish(publisher.readable());
        });
      cancelToken.throwIfCancelled();
      progress?.(`正在生成 ${normalizedFormat.toUpperCase()} 文件`, chapters.length, chapters.length);
      const originalPath = await OnlineBookExporter.write(directory, title, author, description, chapters, normalizedFormat);
      cancelToken.throwIfCancelled();
      const completedBook = publish(chapters, true, originalPath);
      progress?.('下载完成，已加入书架', chapters.length, chapters.length);
      return completedBook;
    } catch (error) {
      const readable = publisher.readable();
      if (incremental && readable.length > 0) publish(readable);
      throw new Error(String(error));
    } finally {
      try { cache.prune(); } catch (error) { /* Cache maintenance cannot invalidate a readable book. */ }
    }
  }

  private async downloadLegacyToLibrary(result: OnlineBookResult, progress?: OnlineProgress): Promise<BookRecord> {
    await this.ensureSources();
    const source = this.sources.find((item: OnlineSource): boolean => item.id === result.sourceId);
    if (source === undefined) {
      throw new Error('书源已不存在，请重新搜索');
    }
    if (progress !== undefined) {
      progress('正在读取书籍信息');
    }
    const bookDocument = await this.requestDocument(result.url, source);
    const title = this.fallback(this.selectValue(bookDocument, source.book.bookName, true), result.bookName);
    const author = this.cleanAuthor(this.fallback(this.selectValue(bookDocument, source.book.author, true), result.author));
    const category = this.fallback(this.selectValue(bookDocument, source.book.category, true), result.category);
    const description = this.selectValue(bookDocument, source.book.intro, true);
    const references = await this.parseToc(source, result.url);
    if (references.length === 0) {
      throw new Error('书源没有返回章节目录');
    }
    const snapshot = LibraryStore.load(this.context);
    const existing = snapshot.books.find((book: BookRecord): boolean => book.title === title && book.author === author);
    if (existing !== undefined && progress !== undefined) {
      progress('已找到书架中的同名书，将在下载完成后更新');
    }
    const chapters = new Array<ChapterRecord>();
    for (let index = 0; index < references.length; index++) {
      if (progress !== undefined) {
        progress(`下载章节 ${index + 1}/${references.length}`);
      }
      const reference = references[index];
      const content = await this.downloadChapter(source, reference);
      chapters.push(new ChapterRecord(reference.title, content));
    }
    if (existing !== undefined) {
      const chapterPath = existing.chapterFilePath.length > 0 ? existing.chapterFilePath :
        `${LibraryStore.bookDirectory(this.context, existing.id)}/chapters.json`;
      LibraryStore.saveChapters(chapterPath, chapters);
      const now = Date.now();
      existing.title = title.length > 0 ? title : result.bookName;
      existing.author = author.length > 0 ? author : '未知作者';
      existing.category = category.length > 0 ? category : existing.category;
      existing.description = description.length > 0 ? description : existing.description;
      existing.fileType = 'txt';
      existing.chapterFilePath = chapterPath;
      existing.totalChapters = chapters.length;
      existing.currentChapterIndex = Math.max(0, Math.min(existing.currentChapterIndex, chapters.length - 1));
      existing.currentPageIndex = 0;
      existing.scrollOffset = 0;
      existing.updatedAt = now;
      existing.syncUpdatedAt = now;
      existing.syncContentHash = '';
      snapshot.books.sort((left: BookRecord, right: BookRecord): number => right.updatedAt - left.updatedAt);
      LibraryStore.save(this.context, snapshot);
      return existing;
    }
    const now = Date.now();
    const id = `${now}_online`;
    const directory = LibraryStore.bookDirectory(this.context, id);
    const book = new BookRecord();
    book.id = id;
    book.title = title.length > 0 ? title : result.bookName;
    book.author = author.length > 0 ? author : '未知作者';
    book.category = category.length > 0 ? category : '网络小说';
    book.description = description;
    book.fileType = 'txt';
    book.originalFilePath = '';
    book.chapterFilePath = `${directory}/chapters.json`;
    book.totalChapters = chapters.length;
    book.createdAt = now;
    book.updatedAt = now;
    LibraryStore.saveChapters(book.chapterFilePath, chapters);
    snapshot.books.push(book);
    snapshot.books.sort((left: BookRecord, right: BookRecord): number => right.updatedAt - left.updatedAt);
    LibraryStore.save(this.context, snapshot);
    return book;
  }

  private async ensureSources(): Promise<void> {
    if (this.sources.length > 0) {
      return;
    }
    const bytes = await this.context.resourceManager.getRawFileContent('online_sources.json');
    const json = util.TextDecoder.create('utf-8').decodeToString(bytes);
    const parsed = JSON.parse(json) as Array<OnlineSource>;
    this.sources = parsed.map((source: OnlineSource): OnlineSource => this.applySourceDefaults(source));
  }

  private applySourceDefaults(raw: OnlineSource): OnlineSource {
    const source = new OnlineSource();
    source.id = raw.id ?? '';
    source.name = raw.name ?? '';
    source.baseUrl = raw.baseUrl ?? '';
    source.enabled = raw.enabled ?? true;
    source.needProxy = raw.needProxy ?? false;
    source.comment = raw.comment ?? '';

    const search = raw.search ?? new SourceSearchRule();
    source.search.url = search.url ?? '';
    source.search.method = search.method ?? 'get';
    source.search.result = search.result ?? '';
    source.search.bookName = search.bookName ?? '';
    source.search.author = search.author ?? '';
    source.search.category = search.category ?? '';
    source.search.latestChapter = search.latestChapter ?? '';
    source.search.lastUpdateTime = search.lastUpdateTime ?? '';
    source.search.status = search.status ?? '';
    source.search.nextPage = search.nextPage ?? '';
    source.search.disabled = search.disabled ?? false;
    source.search.cookies = search.cookies ?? '';
    source.search.minIntervalMillis = search.minIntervalMillis ?? 0;
    const data = search.data ?? new SourceSearchData();
    source.search.data.name = data.name ?? '';
    source.search.data.s = data.s ?? '';
    source.search.data.searchkey = data.searchkey ?? '';
    source.search.data.searchtype = data.searchtype ?? '';
    source.search.data.Submit = data.Submit ?? '';
    source.search.data.type = data.type ?? '';

    const book = raw.book ?? new SourceBookRule();
    source.book.url = book.url ?? '';
    source.book.bookName = book.bookName ?? '';
    source.book.author = book.author ?? '';
    source.book.category = book.category ?? '';
    source.book.intro = book.intro ?? '';

    const toc = raw.toc ?? new SourceTocRule();
    source.toc.url = toc.url ?? '';
    source.toc.baseUri = toc.baseUri ?? '';
    source.toc.item = toc.item ?? '';
    source.toc.nextPage = toc.nextPage ?? '';
    source.toc.isDesc = toc.isDesc ?? false;

    const chapter = raw.chapter ?? new SourceChapterRule();
    source.chapter.title = chapter.title ?? '';
    source.chapter.content = chapter.content ?? '';
    source.chapter.filterTxt = chapter.filterTxt ?? '';
    source.chapter.filterTag = chapter.filterTag ?? '';
    source.chapter.nextPage = chapter.nextPage ?? '';
    source.chapter.nextPageInJs = chapter.nextPageInJs ?? '';
    source.chapter.nextChapterLink = chapter.nextChapterLink ?? '';

    const crawl = raw.crawl ?? new SourceCrawlRule();
    source.crawl.timeoutMillis = crawl.timeoutMillis ?? 15000;
    source.crawl.minIntervalMillis = crawl.minIntervalMillis ?? 0;
    source.crawl.maxIntervalMillis = crawl.maxIntervalMillis ?? source.crawl.minIntervalMillis;
    source.crawl.maxRetries = crawl.maxRetries ?? 2;
    source.crawl.concurrency = Math.max(1, Math.min(8, crawl.concurrency ?? 1));
    return source;
  }

  private async searchSource(source: OnlineSource, keyword: string, cancelToken: OnlineDownloadCancelToken,
    onResults: OnlineSearchResults): Promise<Array<OnlineBookResult>> {
    let url = OnlineRuleAdapter.buildSearchUrl(source.id, source.search.url, keyword);
    let body = '';
    if (source.search.method.toLowerCase() === 'post') {
      const values = new Array<string>();
      this.appendFormValue(values, 'name', source.search.data.name, keyword);
      this.appendFormValue(values, 's', source.search.data.s, keyword);
      this.appendFormValue(values, 'searchkey', source.search.data.searchkey, keyword);
      this.appendFormValue(values, 'searchtype', source.search.data.searchtype, keyword);
      this.appendFormValue(values, 'Submit', source.search.data.Submit, keyword);
      this.appendFormValue(values, 'type', source.search.data.type, keyword);
      body = values.join('&');
    }
    const output = new Array<OnlineBookResult>();
    const pages = new Array<string>();
    pages.push(url);
    const visited = new Set<string>();
    for (let pageIndex = 0; pageIndex < pages.length && pageIndex < 5; pageIndex++) {
      cancelToken.throwIfCancelled();
      const currentUrl = pages[pageIndex];
      visited.add(currentUrl);
      const document = await this.requestDocument(currentUrl, source, pageIndex === 0 ? body : '', true, cancelToken);
      const rows = SimpleHtml.select(document, source.search.result);
      const countBeforePage = output.length;
      rows.forEach((row: HtmlNode): void => this.appendSearchResult(row, source, output));
      if (output.length === countBeforePage) {
        this.appendFallbackSearchResults(document, source, keyword, output);
      }
      onResults(output.slice());
      if (source.search.nextPage.length > 0) {
        const nextNodes = SimpleHtml.select(document, source.search.nextPage);
        for (let nextIndex = 0; nextIndex < nextNodes.length; nextIndex++) {
          const nextUrl = this.nodeUrl(nextNodes[nextIndex]);
          if (nextUrl.length > 0 && !visited.has(nextUrl) && pages.indexOf(nextUrl) < 0 &&
            this.sameHost(url, nextUrl)) {
            pages.push(nextUrl);
          }
        }
      }
    }
    return output;
  }

  private appendSearchResult(scope: HtmlNode, source: OnlineSource, output: Array<OnlineBookResult>): void {
    const bookName = this.selectValue(scope, source.search.bookName, true);
    const bookUrl = this.selectValue(scope, source.search.bookName, false);
    if (bookName.length === 0 || bookUrl.length === 0 ||
      output.some((item: OnlineBookResult): boolean => item.url === bookUrl)) {
      return;
    }
    const item = new OnlineBookResult();
    item.sourceId = source.id;
    item.sourceName = source.name;
    item.bookName = bookName;
    item.url = bookUrl;
    item.author = this.cleanAuthor(this.selectValue(scope, source.search.author, true));
    item.category = this.selectValue(scope, source.search.category, true);
    item.latestChapter = this.selectValue(scope, source.search.latestChapter, true);
    item.lastUpdateTime = this.selectValue(scope, source.search.lastUpdateTime, true);
    item.status = this.selectValue(scope, source.search.status, true);
    output.push(item);
  }

  private appendFallbackSearchResults(document: HtmlNode, source: OnlineSource, keyword: string,
    output: Array<OnlineBookResult>): void {
    let candidates = source.search.bookName.length > 0 ?
      SimpleHtml.select(document, source.search.bookName) : new Array<HtmlNode>();
    if (candidates.length === 0) {
      const normalizedKeyword = SimpleHtml.cleanText(keyword).toLowerCase();
      candidates = SimpleHtml.select(document, 'a').filter((node: HtmlNode): boolean => {
        const title = SimpleHtml.cleanText(node.text());
        if (title.length < 2 || title.length > 80 || node.absoluteUrl('href').length === 0) {
          return false;
        }
        const parentText = node.parent === undefined ? '' : node.parent.text();
        return title.toLowerCase().indexOf(normalizedKeyword) >= 0 ||
          parentText.toLowerCase().indexOf(normalizedKeyword) >= 0;
      });
    }
    candidates.forEach((node: HtmlNode): void => {
      const bookName = SimpleHtml.cleanText(node.text());
      const bookUrl = node.absoluteUrl('href');
      if (bookName.length < 2 || bookName.length > 80 || bookUrl.length === 0 ||
        output.some((item: OnlineBookResult): boolean => item.url === bookUrl)) {
        return;
      }
      const scope = this.searchResultScope(node, source.search.bookName);
      const item = new OnlineBookResult();
      item.sourceId = source.id;
      item.sourceName = source.name;
      item.bookName = bookName;
      item.url = bookUrl;
      item.author = this.cleanAuthor(this.selectValue(scope, source.search.author, true));
      item.category = this.selectValue(scope, source.search.category, true);
      item.latestChapter = this.selectValue(scope, source.search.latestChapter, true);
      item.lastUpdateTime = this.selectValue(scope, source.search.lastUpdateTime, true);
      item.status = this.selectValue(scope, source.search.status, true);
      output.push(item);
    });
  }

  private searchResultScope(node: HtmlNode, bookNameSelector: string): HtmlNode {
    let current = node.parent;
    for (let depth = 0; depth < 8 && current !== undefined; depth++) {
      if (bookNameSelector.length > 0 && SimpleHtml.select(current, bookNameSelector).indexOf(node) >= 0) {
        return current;
      }
      current = current.parent;
    }
    return node.parent === undefined ? node : node.parent;
  }

  private async parseToc(source: OnlineSource, bookUrl: string, bookDocument?: HtmlNode,
    cancelToken: OnlineDownloadCancelToken = new OnlineDownloadCancelToken()): Promise<Array<ChapterReference>> {
    let tocUrl = bookUrl;
    const pattern = source.book.url;
    const template = source.toc.url.length > 0 ? source.toc.url : source.toc.baseUri;
    if (pattern.length > 0 && template.length > 0) {
      try {
        const match = new RegExp(pattern).exec(bookUrl);
        if (match !== null && match.length > 1) {
          tocUrl = template.replace('%s', match[1]);
        }
      } catch (error) {
        tocUrl = bookUrl;
      }
    }
    const references = new Array<ChapterReference>();
    const tocUrls = new Array<string>();
    const visited = new Set<string>();
    const chapterUrls = new Set<string>();
    tocUrls.push(tocUrl);
    for (let pageIndex = 0; pageIndex < tocUrls.length && pageIndex < 20; pageIndex++) {
      const currentUrl = tocUrls[pageIndex];
      if (visited.has(currentUrl)) {
        continue;
      }
      visited.add(currentUrl);
      cancelToken.throwIfCancelled();
      const document = currentUrl === bookUrl && bookDocument !== undefined ? bookDocument :
        await this.requestDocument(currentUrl, source, '', false, cancelToken);
      OnlineRuleAdapter.applyTocTransform(document, source.id);
      const nodes = SimpleHtml.select(document, OnlineRuleAdapter.selector(source.toc.item));
      nodes.forEach((node: HtmlNode): void => {
        const title = node.text();
        const url = this.nodeUrl(node);
        if (title.length > 0 && url.length > 0 && !chapterUrls.has(url)) {
          chapterUrls.add(url);
          const reference = new ChapterReference();
          reference.title = title;
          reference.url = url;
          references.push(reference);
        }
      });
      if (source.toc.nextPage.length > 0) {
        SimpleHtml.select(document, source.toc.nextPage).forEach((node: HtmlNode): void => {
          const nextUrl = this.nodeUrl(node);
          if (nextUrl.length > 0 && !visited.has(nextUrl) && tocUrls.indexOf(nextUrl) < 0) {
            if (!this.sameHost(bookUrl, nextUrl)) return;
            tocUrls.push(nextUrl);
          }
        });
      }
    }
    if (tocUrls.some((url: string): boolean => !visited.has(url))) {
      throw new Error('目录分页超过安全上限，未下载以免生成残缺书籍');
    }
    if (source.toc.isDesc) {
      references.reverse();
    }
    return references;
  }

  private async downloadChapters(source: OnlineSource, references: Array<ChapterReference>, progress: OnlineProgress | undefined,
    cancelToken: OnlineDownloadCancelToken, cache: OnlineChapterCache,
    resumed: Array<ChapterRecord>, onChapter: (index: number, chapter: ChapterRecord) => void): Promise<Array<ChapterRecord>> {
    const contents = new Array<string>(references.length).fill('');
    const workerCount = Math.max(1, Math.min(source.crawl.concurrency, references.length));
    let cursor = 0;
    let completed = 0;
    let failure: Error | undefined = undefined;
    const workerToken = new OnlineDownloadCancelToken();
    const abort = (): void => workerToken.cancel();
    cancelToken.register(abort);
    const knownChapters = new Set<string>(references.map((reference: ChapterReference): string => reference.url));
    const worker = async (): Promise<void> => {
      while (true) {
        workerToken.throwIfCancelled();
        const index = cursor;
        cursor++;
        if (index >= references.length) {
          return;
        }
        const reference = references[index];
        const identity = JSON.stringify([source.id, reference.url, reference.title, source.chapter,
          references[index + 1]?.url ?? '']);
        let content = index < resumed.length ? resumed[index].content : await cache.read(identity);
        if (content.length === 0) {
          content = await this.downloadChapter(source, reference, workerToken, knownChapters);
          workerToken.throwIfCancelled();
          await cache.write(identity, content);
        }
        workerToken.throwIfCancelled();
        contents[index] = content;
        onChapter(index, new ChapterRecord(reference.title, content));
        completed++;
        progress?.(`下载章节 ${completed}/${references.length} · ${reference.title}`, completed, references.length);
      }
    };
    const workers = new Array<Promise<void>>();
    for (let index = 0; index < workerCount; index++) {
      workers.push(worker().catch((error: Error): void => {
        if (failure === undefined) failure = error;
        workerToken.cancel();
      }));
    }
    await Promise.all(workers);
    cancelToken.unregister(abort);
    cancelToken.throwIfCancelled();
    if (failure !== undefined) throw new Error(String(failure));
    return references.map((reference: ChapterReference, index: number): ChapterRecord =>
      new ChapterRecord(reference.title, contents[index]));
  }

  private async downloadChapter(source: OnlineSource, reference: ChapterReference,
    cancelToken: OnlineDownloadCancelToken = new OnlineDownloadCancelToken(),
    knownChapters: Set<string> = new Set<string>()): Promise<string> {
    let lastError = '';
    for (let attempt = 0; attempt <= Math.max(0, source.crawl.maxRetries); attempt++) {
      try {
        cancelToken.throwIfCancelled();
        if (attempt > 0) {
          await this.delay(Math.max(500, source.crawl.minIntervalMillis) * attempt, cancelToken);
        }
        const pages = new Array<string>();
        const visited = new Set<string>();
        const parts = new Array<string>();
        pages.push(reference.url);
        for (let pageIndex = 0; pageIndex < pages.length && pageIndex < 50; pageIndex++) {
          cancelToken.throwIfCancelled();
          const pageUrl = pages[pageIndex];
          if (visited.has(pageUrl)) {
            continue;
          }
          visited.add(pageUrl);
          const document = await this.requestDocument(pageUrl, source, '', false, cancelToken);
          const contentNodes = SimpleHtml.select(document, OnlineRuleAdapter.selector(source.chapter.content));
          if (contentNodes.length === 0) {
            throw new Error('正文为空');
          }
          const pageParts = new Array<string>();
          contentNodes.forEach((content: HtmlNode): void => {
            OnlineRuleAdapter.prepareChapterContent(content, source.chapter.content);
            if (source.chapter.filterTag.length > 0) {
              SimpleHtml.select(content, source.chapter.filterTag).forEach((node: HtmlNode): void => node.remove());
            }
            const contentText = this.normalizeParagraphs(OnlineRuleAdapter.chapterText(content, source.chapter.content));
            if (contentText.length > 0) {
              pageParts.push(contentText);
            }
          });
          let text = pageParts.join('\n\n');
          if (source.chapter.filterTxt.length > 0) {
            try {
              text = text.replace(new RegExp(source.chapter.filterTxt, 'g'), '');
            } catch (error) {
              // An invalid site-side filter should not discard a successfully downloaded chapter.
            }
          }
          const normalized = this.normalizeParagraphs(text);
          if (normalized.length > 0) {
            parts.push(normalized);
          }
          if (source.chapter.nextPage.length > 0) {
            const nextNodes = SimpleHtml.select(document, source.chapter.nextPage);
            if (nextNodes.length > 0) {
              const label = nextNodes[0].text();
              const nextUrl = this.nodeUrl(nextNodes[0]);
              if (!knownChapters.has(nextUrl) && this.isChapterPageLink(source, pageUrl, nextUrl, label, visited)) {
                pages.push(nextUrl);
              }
            }
          }
          if (pages.length === pageIndex + 1 && source.chapter.nextPageInJs.length > 0) {
            const selector = source.chapter.nextPageInJs.split('@js:')[0];
            const scriptNodes = SimpleHtml.select(document, selector);
            if (scriptNodes.length > 0) {
              const match = scriptNodes[0].text().match(/nextpage\s*=\s*[\\]?['"]([^'"]+)['"]/i);
              if (match !== null) {
                const nextUrl = SimpleHtml.resolveUrl(pageUrl, match[1]);
                if (!knownChapters.has(nextUrl) && this.isChapterPageLink(source, pageUrl, nextUrl, '', visited)) {
                  pages.push(nextUrl);
                }
              }
            }
          }
        }
        if (pages.some((url: string): boolean => !visited.has(url))) {
          throw new Error('章节分页超过安全上限，不缓存残缺正文');
        }
        const text = parts.join('\n\n');
        if (text.length === 0) {
          throw new Error('正文为空');
        }
        return text;
      } catch (error) {
        cancelToken.throwIfCancelled();
        if (error instanceof OnlineHttpError && !error.retryable) throw error as OnlineHttpError;
        lastError = String(error);
      }
    }
    throw new Error(`${reference.title} 下载失败：${lastError}`);
  }

  private async requestDocument(url: string, source: OnlineSource, body: string = '',
    preprocessSearch: boolean = false,
    cancelToken: OnlineDownloadCancelToken = new OnlineDownloadCancelToken()): Promise<HtmlNode> {
    const retries = preprocessSearch ? Math.min(1, source.crawl.maxRetries) : source.crawl.maxRetries;
    const timeoutMillis = Math.max(1, preprocessSearch ?
      Math.min(source.crawl.timeoutMillis, this.searchOptions.requestTimeoutMillis) : source.crawl.timeoutMillis);
    for (let attempt = 0; ; attempt++) {
    await this.waitForSource(source, preprocessSearch, cancelToken);
    const request = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: body.length > 0 ? http.RequestMethod.POST : http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: timeoutMillis,
      readTimeout: timeoutMillis
    };
    if (body.length > 0) {
      options.header = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
        'Referer': source.baseUrl.replace(/\/+$/, ''),
        'Cookie': preprocessSearch ? source.search.cookies : '',
        'Accept': 'text/html,application/xhtml+xml',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
      };
      options.extraData = body;
    } else {
      options.header = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
        'Referer': source.baseUrl.replace(/\/+$/, ''),
        'Cookie': preprocessSearch ? source.search.cookies : '',
        'Accept': 'text/html,application/xhtml+xml'
      };
    }
    try {
      const response = await this.requestResponse(request, url, options, timeoutMillis, cancelToken);
      cancelToken.throwIfCancelled();
      if (response.responseCode === 429 || response.responseCode === 408 || response.responseCode >= 500) {
        const header = response.header as Record<string, string>;
        const retryAfter = header['retry-after'] ?? header['Retry-After'] ?? '';
        const seconds = Number(retryAfter);
        const retryMillis = retryAfter.length === 0 ? 0 : Number.isFinite(seconds) ? seconds * 1000 :
          Math.max(0, Date.parse(retryAfter) - Date.now());
        OnlineBookService.backoffUntil.set(source.id, Date.now() +
          Math.min(120000, Math.max(1000 * Math.pow(2, attempt), retryMillis || 0)));
        throw new OnlineHttpError(`HTTP ${response.responseCode}`, true);
      }
      if (response.responseCode < 200 || response.responseCode >= 400) {
        throw new OnlineHttpError(`HTTP ${response.responseCode}`, false);
      }
      const bytes = new Uint8Array(response.result as ArrayBuffer);
      let html = util.TextDecoder.create('utf-8').decodeToString(bytes);
      const headers = response.header as Record<string, string>;
      const contentType = headers['content-type'] ?? headers['Content-Type'] ?? '';
      const declared = /charset\s*=\s*["']?([a-z0-9_-]+)/i.exec(contentType) ??
        /<meta[^>]+charset\s*=\s*["']?([a-z0-9_-]+)/i.exec(html);
      let encoding = declared === null ? '' : declared[1].toLowerCase();
      if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) encoding = 'utf-16le';
      else if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) encoding = 'utf-16be';
      if (encoding === 'gbk' || encoding === 'gb2312') encoding = 'gb18030';
      if (encoding.length > 0 && encoding !== 'utf-8' && encoding !== 'utf8') {
        try { html = util.TextDecoder.create(encoding).decodeToString(bytes); } catch (error) { /* Keep UTF-8 if unavailable. */ }
      } else if (this.replacementCount(html) * 200 > Math.max(1, html.length)) {
        try {
          html = util.TextDecoder.create('gb18030').decodeToString(bytes);
        } catch (error) {
          // Keep UTF-8 output if the platform image does not provide the legacy decoder.
        }
      }
      html = html.replace(/^\uFEFF/, '');
      if (preprocessSearch) {
        html = OnlineRuleAdapter.preprocessSearchHtml(source.id, html);
      }
      if (/(访问过于频繁|请求过于频繁|操作过于频繁|访问频率过高|too many requests|rate limit exceeded)/i.test(html)) {
        OnlineBookService.backoffUntil.set(source.id, Date.now() + 2000 * Math.pow(2, attempt));
        throw new OnlineHttpError('站点限流，请稍后重试', true);
      }
      return SimpleHtml.parse(html, url);
    } catch (error) {
      cancelToken.throwIfCancelled();
      if (error instanceof OnlineHttpError && (!error.retryable || attempt >= retries)) {
        throw error as OnlineHttpError;
      }
      if (attempt >= retries) throw new Error(String(error));
      await this.delay(Math.min(15000, 500 * Math.pow(2, attempt)), cancelToken);
    } finally {
      request.destroy();
    }
    }
  }

  private async requestResponse(request: http.HttpRequest, url: string, options: http.HttpRequestOptions,
    timeoutMillis: number, token: OnlineDownloadCancelToken): Promise<http.HttpResponse> {
    token.throwIfCancelled();
    return new Promise<http.HttpResponse>((resolve: (response: http.HttpResponse) => void,
      reject: (error: Error) => void): void => {
      let settled = false;
      let timer = 0;
      const cleanup = (): void => {
        clearTimeout(timer);
        token.unregister(abort);
      };
      const fail = (error: Error): void => {
        if (settled) return;
        settled = true;
        cleanup();
        reject(error);
        try { request.destroy(); } catch (destroyError) { /* Promise is already settled. */ }
      };
      // Do not rely on destroy() to settle the platform request promise.
      const abort = (): void => fail(new Error(token.reason));
      timer = setTimeout((): void => fail(new Error('网络请求超时')), timeoutMillis);
      token.register(abort);
      if (settled) return;
      try {
        request.request(url, options).then((response: http.HttpResponse): void => {
          if (settled) return;
          settled = true;
          cleanup();
          resolve(response);
        }, (error: BusinessError): void => fail(new Error(ErrorText.from(error))));
      } catch (error) {
        fail(new Error(ErrorText.from(error as BusinessError)));
      }
    });
  }

  private async waitForSource(source: OnlineSource, searching: boolean,
    token: OnlineDownloadCancelToken): Promise<void> {
    token.throwIfCancelled();
    const minimum = Math.max(0, searching ? Math.max(source.search.minIntervalMillis,
      source.crawl.minIntervalMillis) : source.crawl.minIntervalMillis);
    const maximum = Math.max(minimum, source.crawl.maxIntervalMillis);
    const interval = minimum + Math.floor(Math.random() * (maximum - minimum + 1));
    const now = Date.now();
    const key = `${source.id}:${searching ? 'search' : 'crawl'}`;
    const reservedAt = Math.max(now, OnlineBookService.nextRequestAt.get(key) ?? 0,
      OnlineBookService.backoffUntil.get(source.id) ?? 0);
    OnlineBookService.nextRequestAt.set(key, reservedAt +
      Math.ceil(interval / (searching ? 1 : source.crawl.concurrency)));
    const remaining = reservedAt - now;
    if (remaining > 0) {
      await this.delay(remaining, token);
    }
    token.throwIfCancelled();
    const additionalBackoff = (OnlineBookService.backoffUntil.get(source.id) ?? 0) - Date.now();
    if (additionalBackoff > 0) await this.delay(additionalBackoff, token);
  }

  private async delay(milliseconds: number, token: OnlineDownloadCancelToken): Promise<void> {
    token.throwIfCancelled();
    await new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      let timer = 0;
      const abort = (): void => {
        clearTimeout(timer);
        token.unregister(abort);
        reject(new Error(token.reason));
      };
      timer = setTimeout((): void => { token.unregister(abort); resolve(); }, milliseconds);
      token.register(abort);
    });
  }

  private isChapterPageLink(source: OnlineSource, currentUrl: string, nextUrl: string, label: string,
    visited: Set<string>): boolean {
    if (nextUrl.length === 0 || nextUrl === currentUrl || visited.has(nextUrl) || !this.sameHost(currentUrl, nextUrl)) {
      return false;
    }
    const normalizedLabel = SimpleHtml.cleanText(label).toLowerCase();
    if (/下一章|下章|没有了|已完结|next\s*chapter|end/.test(normalizedLabel)) {
      return false;
    }
    if (source.chapter.nextChapterLink.length > 0) {
      try {
        if (new RegExp(source.chapter.nextChapterLink, 'i').test(nextUrl)) {
          return false;
        }
      } catch (error) {
        // Ignore a broken optional rule and retain the generic safeguards.
      }
    }
    return true;
  }

  private sameHost(left: string, right: string): boolean {
    const host = (value: string): string => {
      const match = /^https?:\/\/([^/?#]+)/i.exec(value.trim());
      return match === null ? '' : match[1].toLowerCase().replace(/^www\./, '');
    };
    const leftHost = host(left);
    const rightHost = host(right);
    return leftHost.length > 0 && leftHost === rightHost;
  }

  private plainSelector(rule: string): string {
    if (rule === undefined || rule.trim().length === 0) {
      return '';
    }
    const jsIndex = rule.indexOf('@js:');
    const javaIndex = rule.indexOf('@java:');
    let end = rule.length;
    if (jsIndex >= 0) {
      end = Math.min(end, jsIndex);
    }
    if (javaIndex >= 0) {
      end = Math.min(end, javaIndex);
    }
    const selector = rule.substring(0, end).trim();
    return selector.startsWith('/') ? '' : selector;
  }

  private nodeUrl(node: HtmlNode): string {
    const href = node.absoluteUrl('href');
    if (href.length > 0) {
      return href;
    }
    const value = node.absoluteUrl('value');
    if (value.length > 0) {
      return value;
    }
    return node.absoluteUrl('data-url');
  }

  private selectValue(scope: HtmlNode, rule: string, preferText: boolean): string {
    if (rule === undefined || rule.trim().length === 0) {
      return '';
    }
    const selector = OnlineRuleAdapter.selector(rule);
    const nodes = SimpleHtml.select(scope, selector);
    if (nodes.length === 0) {
      return '';
    }
    const node = nodes[0];
    if (!preferText) {
      const href = node.absoluteUrl('href');
      if (href.length > 0) {
        return href;
      }
    }
    const content = node.attr('content');
    return SimpleHtml.cleanText(content.length > 0 ? content : node.text());
  }

  private genericBookTitle(document: HtmlNode): string {
    const selectors = ['meta[property="og:novel:book_name"]', 'meta[name="og:novel:book_name"]', 'meta[property="og:title"]',
      'meta[name="book_name"]', 'h1'];
    for (let index = 0; index < selectors.length; index++) {
      const value = this.selectValue(document, selectors[index], true);
      if (value.length > 0) {
        return value.replace(/[-_｜|].*$/, '').trim();
      }
    }
    return '网络小说';
  }

  private genericBookAuthor(document: HtmlNode): string {
    const selectors = ['meta[property="og:novel:author"]', 'meta[name="og:novel:author"]',
      'meta[name="author"]'];
    for (let index = 0; index < selectors.length; index++) {
      const value = this.selectValue(document, selectors[index], true);
      if (value.length > 0) {
        return value;
      }
    }
    return '未知作者';
  }

  private appendFormValue(output: Array<string>, key: string, value: string, keyword: string): void {
    if (value === undefined || value.length === 0) {
      return;
    }
    output.push(`${encodeURIComponent(key)}=${encodeURIComponent(value === '%s' ? keyword : value)}`);
  }

  private cleanAuthor(value: string): string {
    return SimpleHtml.cleanText(value).replace(/^(作者|作 者)[:：\s]*/, '').trim();
  }

  private normalizeParagraphs(value: string): string {
    return value.split(/\r?\n+/).map((line: string): string => line.trim()).filter((line: string): boolean => line.length > 0).join('\n\n');
  }

  private fallback(value: string, fallback: string): string {
    return value.trim().length > 0 ? value.trim() : fallback.trim();
  }

  private replacementCount(value: string): number {
    let count = 0;
    for (let index = 0; index < value.length; index++) {
      if (value.charAt(index) === '\uFFFD') {
        count++;
      }
    }
    return count;
  }
}
