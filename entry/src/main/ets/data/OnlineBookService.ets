import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BookRecord, ChapterRecord, LibrarySnapshot, OnlineBookResult } from '../model/Models';
import { ErrorText } from './ErrorText';
import { LibraryStore } from './LibraryStore';
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
  maxRetries: number = 2;
}

class OnlineSource {
  id: string = '';
  name: string = '';
  baseUrl: string = '';
  enabled: boolean = true;
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

export type OnlineProgress = (message: string) => void;

export class OnlineBookService {
  private context: common.UIAbilityContext;
  private sources: Array<OnlineSource> = new Array<OnlineSource>();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async search(keyword: string, progress?: OnlineProgress): Promise<Array<OnlineBookResult>> {
    await this.ensureSources();
    const enabled = this.sources.filter((source: OnlineSource): boolean => source.enabled && !source.search.disabled &&
      source.search.url.length > 0 && source.search.result.length > 0);
    const output = new Array<OnlineBookResult>();
    let failedSources = 0;
    for (let index = 0; index < enabled.length; index++) {
      const source = enabled[index];
      if (progress !== undefined) {
        progress(`正在搜索 ${source.name}（${index + 1}/${enabled.length}）`);
      }
      try {
        const results = await this.searchSource(source, keyword);
        results.forEach((item: OnlineBookResult): void => {
          const duplicated = output.some((existing: OnlineBookResult): boolean => existing.url === item.url);
          if (!duplicated) {
            output.push(item);
          }
        });
      } catch (error) {
        failedSources++;
        if (progress !== undefined) {
          progress(`${source.name} 失败：${ErrorText.from(error as BusinessError)}`);
        }
      }
    }
    if (output.length === 0 && enabled.length > 0) {
      if (failedSources === enabled.length) {
        throw new Error(`全部 ${enabled.length} 个书源连接失败，请检查网络后重试`);
      }
      const connected = enabled.length - failedSources;
      const suffix = failedSources > 0 ? `，另有 ${failedSources} 个书源连接失败` : '';
      throw new Error(`已连接 ${connected} 个书源，但没有解析到匹配结果${suffix}；书源页面可能已改版`);
    }
    return output;
  }

  async downloadToLibrary(result: OnlineBookResult, progress?: OnlineProgress): Promise<BookRecord> {
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
    const chapters = new Array<ChapterRecord>();
    for (let index = 0; index < references.length; index++) {
      if (progress !== undefined) {
        progress(`下载章节 ${index + 1}/${references.length}`);
      }
      const reference = references[index];
      const content = await this.downloadChapter(source, reference);
      chapters.push(new ChapterRecord(reference.title, content));
    }
    const snapshot = LibraryStore.load(this.context);
    const existing = snapshot.books.find((book: BookRecord): boolean => book.title === title && book.author === author);
    if (existing !== undefined) {
      throw new Error('书架中已有同名同作者书籍');
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
    source.crawl.maxRetries = crawl.maxRetries ?? 2;
    return source;
  }

  private async searchSource(source: OnlineSource, keyword: string): Promise<Array<OnlineBookResult>> {
    let url = source.search.url;
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
    } else {
      url = url.replace('%s', encodeURIComponent(keyword));
    }
    const output = new Array<OnlineBookResult>();
    const pages = new Array<HtmlNode>();
    pages.push(await this.requestDocument(url, source, body));
    const visited = new Set<string>();
    for (let pageIndex = 0; pageIndex < pages.length && pageIndex < 5; pageIndex++) {
      const document = pages[pageIndex];
      const rows = SimpleHtml.select(document, source.search.result);
      const countBeforePage = output.length;
      rows.forEach((row: HtmlNode): void => this.appendSearchResult(row, source, output));
      if (output.length === countBeforePage) {
        this.appendFallbackSearchResults(document, source, keyword, output);
      }
      if (source.search.nextPage.length > 0) {
        const nextNodes = SimpleHtml.select(document, source.search.nextPage);
        for (let nextIndex = 0; nextIndex < nextNodes.length; nextIndex++) {
          const nextUrl = nextNodes[nextIndex].absoluteUrl('href');
          if (nextUrl.length > 0 && !visited.has(nextUrl)) {
            visited.add(nextUrl);
            pages.push(await this.requestDocument(nextUrl, source));
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

  private async parseToc(source: OnlineSource, bookUrl: string): Promise<Array<ChapterReference>> {
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
    tocUrls.push(tocUrl);
    for (let pageIndex = 0; pageIndex < tocUrls.length && pageIndex < 20; pageIndex++) {
      const currentUrl = tocUrls[pageIndex];
      if (visited.has(currentUrl)) {
        continue;
      }
      visited.add(currentUrl);
      const document = await this.requestDocument(currentUrl, source);
      const nodes = SimpleHtml.select(document, source.toc.item);
      nodes.forEach((node: HtmlNode): void => {
        const title = node.text();
        const url = node.absoluteUrl('href');
        if (title.length > 0 && url.length > 0 && !references.some((item: ChapterReference): boolean => item.url === url)) {
          const reference = new ChapterReference();
          reference.title = title;
          reference.url = url;
          references.push(reference);
        }
      });
      if (source.toc.nextPage.length > 0) {
        SimpleHtml.select(document, source.toc.nextPage).forEach((node: HtmlNode): void => {
          const nextUrl = node.absoluteUrl('href');
          if (nextUrl.length > 0 && !visited.has(nextUrl) && tocUrls.indexOf(nextUrl) < 0) {
            tocUrls.push(nextUrl);
          }
        });
      }
    }
    if (source.toc.isDesc) {
      references.reverse();
    }
    return references;
  }

  private async downloadChapter(source: OnlineSource, reference: ChapterReference): Promise<string> {
    let lastError = '';
    for (let attempt = 0; attempt <= Math.max(0, source.crawl.maxRetries); attempt++) {
      try {
        const pages = new Array<string>();
        const visited = new Set<string>();
        const parts = new Array<string>();
        pages.push(reference.url);
        for (let pageIndex = 0; pageIndex < pages.length && pageIndex < 50; pageIndex++) {
          const pageUrl = pages[pageIndex];
          if (visited.has(pageUrl)) {
            continue;
          }
          visited.add(pageUrl);
          const document = await this.requestDocument(pageUrl, source);
          const contentNodes = SimpleHtml.select(document, source.chapter.content);
          if (contentNodes.length === 0) {
            throw new Error('正文为空');
          }
          const content = contentNodes[0];
          if (source.chapter.filterTag.length > 0) {
            SimpleHtml.select(content, source.chapter.filterTag).forEach((node: HtmlNode): void => node.remove());
          }
          let text = content.text();
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
              const nextUrl = nextNodes[0].absoluteUrl('href');
              if (nextUrl.length > 0 && nextUrl !== pageUrl && !visited.has(nextUrl) &&
                label.indexOf('下一章') < 0 && label.indexOf('next chapter') < 0) {
                pages.push(nextUrl);
              }
            }
          } else if (source.chapter.nextPageInJs.length > 0) {
            const selector = source.chapter.nextPageInJs.split('@js:')[0];
            const scriptNodes = SimpleHtml.select(document, selector);
            if (scriptNodes.length > 0) {
              const match = scriptNodes[0].text().match(/nextpage\s*=\s*[\\]?['"]([^'"]+)['"]/i);
              if (match !== null) {
                const nextUrl = SimpleHtml.resolveUrl(pageUrl, match[1]);
                if (nextUrl.length > 0 && !visited.has(nextUrl)) {
                  pages.push(nextUrl);
                }
              }
            }
          }
        }
        const text = parts.join('\n\n');
        if (text.length === 0) {
          throw new Error('正文为空');
        }
        return text;
      } catch (error) {
        lastError = String(error);
      }
    }
    throw new Error(`${reference.title} 下载失败：${lastError}`);
  }

  private async requestDocument(url: string, source: OnlineSource, body: string = ''): Promise<HtmlNode> {
    const request = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: body.length > 0 ? http.RequestMethod.POST : http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: source.crawl.timeoutMillis,
      readTimeout: source.crawl.timeoutMillis
    };
    if (body.length > 0) {
      options.header = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
        'Referer': source.baseUrl,
        'Accept': 'text/html,application/xhtml+xml',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
      };
      options.extraData = body;
    } else {
      options.header = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
        'Referer': source.baseUrl,
        'Accept': 'text/html,application/xhtml+xml'
      };
    }
    try {
      const response = await request.request(url, options);
      if (response.responseCode < 200 || response.responseCode >= 400) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      const bytes = new Uint8Array(response.result as ArrayBuffer);
      let html = util.TextDecoder.create('utf-8').decodeToString(bytes);
      if (this.replacementCount(html) * 200 > Math.max(1, html.length)) {
        try {
          html = util.TextDecoder.create('gb18030').decodeToString(bytes);
        } catch (error) {
          // Keep UTF-8 output if the platform image does not provide the legacy decoder.
        }
      }
      return SimpleHtml.parse(html, url);
    } finally {
      request.destroy();
    }
  }

  private selectValue(scope: HtmlNode, rule: string, preferText: boolean): string {
    if (rule === undefined || rule.trim().length === 0) {
      return '';
    }
    const selector = rule.split('@js:')[0];
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
