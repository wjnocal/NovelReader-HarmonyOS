import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError, zlib } from '@kit.BasicServicesKit';
import {
  BookRecord,
  BookmarkRecord,
  ChapterRecord,
  DailyReadingRecord,
  LibrarySnapshot,
  NoteRecord,
  SyncTombstoneRecord,
  WebDavConfig
} from '../model/Models';
import { ErrorText } from './ErrorText';
import { LibraryStore } from './LibraryStore';

const SYNC_ROOT = 'NovelReaderSync/';
const MANIFEST_PATH = `${SYNC_ROOT}manifest.json`;
const CONFIG_FILE = 'webdav.json';

class DavResponse {
  code: number = 0;
  data: Uint8Array = new Uint8Array(0);
  headers: string = '';
}

class SyncProfile {
  name: string = '默认用户';
  nameUpdatedAt: number = 0;
  avatarHash: string = '';
  avatarUpdatedAt: number = 0;
}

class SyncReaderSettings {
  updatedAt: number = 0;
  textSizeSp: number = 19;
  lineSpacingMultiplier: number = 1.65;
  themeMode: number = 0;
  readMode: number = 1;
  fontMode: number = 0;
  paragraphSpacingDp: number = 0;
  firstLineIndentEm: number = 2;
  pageMarginDp: number = 22;
  pageTurnMode: number = 0;
}

class SyncBook {
  syncId: string = '';
  contentHash: string = '';
  updatedAt: number = 0;
  title: string = '';
  author: string = '';
  fileType: string = 'txt';
  category: string = '未分类';
  description: string = '';
  totalChapters: number = 0;
  currentChapterIndex: number = 0;
  scrollY: number = 0;
  currentPageIndex: number = 0;
  currentPageStartOffset: number = 0;
  chapterSplitMode: number = 0;
  pinnedAt: number = 0;
  finishedAt: number = 0;
  createdAt: number = 0;
}

class SyncBookmark {
  syncId: string = '';
  bookSyncId: string = '';
  chapterIndex: number = 0;
  pageIndex: number = 0;
  pageStartOffset: number = 0;
  chapterTitle: string = '';
  summary: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;
}

class SyncNote {
  syncId: string = '';
  bookSyncId: string = '';
  chapterIndex: number = 0;
  pageIndex: number = 0;
  pageStartOffset: number = 0;
  chapterTitle: string = '';
  selectedText: string = '';
  noteText: string = '';
  color: number = 0x66FFE08A;
  createdAt: number = 0;
  updatedAt: number = 0;
}

class SyncFolder {
  syncId: string = '';
  name: string = '';
  pinnedAt: number = 0;
  updatedAt: number = 0;
}

class SyncReadingEvent {
  syncId: string = '';
  date: string = '';
  readingMillis: number = 0;
  createdAt: number = 0;
}

class SyncTombstone {
  type: string = '';
  syncId: string = '';
  deletedAt: number = 0;
}

class SyncManifest {
  schema: number = 1;
  deviceId: string = '';
  updatedAt: number = 0;
  profile: SyncProfile = new SyncProfile();
  readerSettings: SyncReaderSettings = new SyncReaderSettings();
  books: Array<SyncBook> = new Array<SyncBook>();
  bookmarks: Array<SyncBookmark> = new Array<SyncBookmark>();
  notes: Array<SyncNote> = new Array<SyncNote>();
  folders: Array<SyncFolder> = new Array<SyncFolder>();
  readingEvents: Array<SyncReadingEvent> = new Array<SyncReadingEvent>();
  tombstones: Array<SyncTombstone> = new Array<SyncTombstone>();
}

class ArchiveChapterMeta {
  index: number = 0;
  title: string = '';
  path: string = '';
}

class ArchiveMeta {
  format: number = 1;
  original: string = '';
  cover: string = '';
  chapters: Array<ArchiveChapterMeta> = new Array<ArchiveChapterMeta>();
}

class ArchiveResult {
  path: string = '';
  sha256: string = '';
}

export type WebDavProgress = (message: string, percent: number) => void;

class WebDavClient {
  private config: WebDavConfig;
  private authorization: string;

  constructor(config: WebDavConfig) {
    this.config = config;
    const credentials = new util.TextEncoder().encodeInto(`${config.username}:${config.password}`);
    this.authorization = `Basic ${new util.Base64Helper().encodeToStringSync(credentials)}`;
  }

  async test(): Promise<void> {
    const response = await this.request('PROPFIND', '', new Uint8Array(0), '0');
    if (response.code !== 207 && !this.success(response.code)) {
      throw new Error(this.errorMessage('WebDAV 连接失败', response.code));
    }
  }

  async ensureDirectory(path: string): Promise<void> {
    let current = '';
    const segments = path.split('/');
    for (let index = 0; index < segments.length; index++) {
      if (segments[index].length === 0) {
        continue;
      }
      current += `${segments[index]}/`;
      const response = await this.request('MKCOL', current, new Uint8Array(0));
      if (!this.success(response.code) && response.code !== 405) {
        throw new Error(this.errorMessage('无法创建同步目录', response.code));
      }
    }
  }

  async exists(path: string): Promise<boolean> {
    const response = await this.request('HEAD', path);
    if (this.success(response.code)) {
      return true;
    }
    if (response.code === 405) {
      const property = await this.request('PROPFIND', path, new Uint8Array(0), '0');
      return property.code === 207 || this.success(property.code);
    }
    return false;
  }

  async etag(path: string): Promise<string> {
    const response = await this.request('HEAD', path);
    if (response.code === 404) {
      return '';
    }
    const jsonMatch = response.headers.match(/"etag"\s*:\s*"((?:\\.|[^"])*)"/i);
    if (jsonMatch !== null) {
      return jsonMatch[1].replace(/\\"/g, '"');
    }
    const plainMatch = response.headers.match(/etag\s*[:=]\s*([^\r\n,\x7D]+)/i);
    return plainMatch === null ? '' : plainMatch[1].trim();
  }

  async get(path: string): Promise<Uint8Array | undefined> {
    const response = await this.request('GET', path);
    if (response.code === 404) {
      return undefined;
    }
    if (!this.success(response.code)) {
      throw new Error(this.errorMessage('下载同步数据失败', response.code));
    }
    return response.data;
  }

  async putAtomic(path: string, bytes: Uint8Array, ifMatch: string = ''): Promise<void> {
    const temporary = `${path}.cache-${WebDavSyncService.uuid()}`;
    const staged = await this.request('PUT', temporary, bytes);
    if (!this.success(staged.code)) {
      throw new Error(this.errorMessage('上传同步数据失败', staged.code));
    }
    const destination = this.urlFor(path);
    const moved = await this.request('MOVE', temporary, new Uint8Array(0), '', destination, ifMatch);
    if (moved.code === 412) {
      throw new Error('服务器数据已被另一台设备更新，请重试');
    }
    if (this.success(moved.code)) {
      return;
    }
    const direct = await this.request('PUT', path, bytes, '', '', ifMatch);
    if (!this.success(direct.code)) {
      throw new Error(this.errorMessage('发布同步数据失败', direct.code));
    }
  }

  private async request(method: string, path: string, body?: Uint8Array, depth: string = '',
    destination: string = '', ifMatch: string = ''): Promise<DavResponse> {
    const request = http.createHttp();
    const options: http.HttpRequestOptions = {
      customMethod: method,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 20000,
      readTimeout: 30000
    };
    if (body !== undefined && body.byteLength > 0) {
      options.extraData = body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength);
    }
    if (destination.length > 0 && ifMatch.length > 0) {
      options.header = {
        'Authorization': this.authorization, 'User-Agent': 'NovelReader-WebDAV/3.0',
        'Accept': '*/*', 'Accept-Charset': 'utf-8', 'Content-Type': 'application/octet-stream',
        'Destination': destination, 'Overwrite': 'T', 'If-Match': ifMatch
      };
    } else if (destination.length > 0) {
      options.header = {
        'Authorization': this.authorization, 'User-Agent': 'NovelReader-WebDAV/3.0',
        'Accept': '*/*', 'Accept-Charset': 'utf-8', 'Content-Type': 'application/octet-stream',
        'Destination': destination, 'Overwrite': 'T'
      };
    } else if (ifMatch.length > 0) {
      options.header = {
        'Authorization': this.authorization, 'User-Agent': 'NovelReader-WebDAV/3.0',
        'Accept': '*/*', 'Accept-Charset': 'utf-8', 'Content-Type': 'application/octet-stream', 'If-Match': ifMatch
      };
    } else if (depth.length > 0) {
      options.header = {
        'Authorization': this.authorization, 'User-Agent': 'NovelReader-WebDAV/3.0',
        'Accept': '*/*', 'Accept-Charset': 'utf-8', 'Content-Type': 'text/xml; charset=utf-8', 'Depth': depth
      };
    } else {
      options.header = {
        'Authorization': this.authorization, 'User-Agent': 'NovelReader-WebDAV/3.0',
        'Accept': '*/*', 'Accept-Charset': 'utf-8', 'Content-Type': 'application/octet-stream'
      };
    }
    try {
      const response = await request.request(this.urlFor(path), options);
      const output = new DavResponse();
      output.code = response.responseCode;
      output.headers = JSON.stringify(response.header);
      if (response.result instanceof ArrayBuffer) {
        output.data = new Uint8Array(response.result as ArrayBuffer);
      }
      return output;
    } catch (error) {
      throw new Error(`WebDAV 网络请求失败：${ErrorText.from(error as BusinessError)}`);
    } finally {
      request.destroy();
    }
  }

  private urlFor(path: string): string {
    const base = this.config.url.endsWith('/') ? this.config.url : `${this.config.url}/`;
    return `${base}${path.split('/').map((part: string): string => encodeURIComponent(part)).join('/')}`;
  }

  private success(code: number): boolean {
    return code >= 200 && code < 300;
  }

  private errorMessage(prefix: string, code: number): string {
    return code === 401 || code === 403 ? `${prefix}：用户名或应用密码错误` : `${prefix}：HTTP ${code}`;
  }
}

export class WebDavSyncService {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  loadConfig(): WebDavConfig {
    try {
      const json = fs.readTextSync(this.configPath());
      return JSON.parse(json) as WebDavConfig;
    } catch (error) {
      return new WebDavConfig();
    }
  }

  saveConfig(config: WebDavConfig): void {
    config.url = config.url.trim();
    config.username = config.username.trim();
    config.enabled = config.url.length > 0;
    this.writeText(this.configPath(), JSON.stringify(config));
  }

  async test(config: WebDavConfig): Promise<void> {
    this.validateConfig(config);
    await new WebDavClient(config).test();
  }

  async sync(config: WebDavConfig, progress?: WebDavProgress): Promise<LibrarySnapshot> {
    this.validateConfig(config);
    const client = new WebDavClient(config);
    this.progress(progress, '连接 WebDAV 服务器', 4);
    await client.test();
    await client.ensureDirectory(`${SYNC_ROOT}objects/`);
    await client.ensureDirectory(`${SYNC_ROOT}avatars/`);
    await client.ensureDirectory(`${SYNC_ROOT}tmp/`);
    await client.ensureDirectory(`${SYNC_ROOT}history/`);
    const etag = await client.etag(MANIFEST_PATH);
    const remoteBytes = await client.get(MANIFEST_PATH);
    let remote = new SyncManifest();
    if (remoteBytes !== undefined && remoteBytes.length > 0) {
      remote = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(remoteBytes)) as SyncManifest;
      this.normalizeManifest(remote);
    }
    let snapshot = LibraryStore.load(this.context);
    this.prepareLocal(snapshot, remote.updatedAt === 0);
    this.progress(progress, '合并服务器数据', 18);
    await this.mergeRemote(snapshot, remote, client, progress);
    this.progress(progress, '准备并上传书籍', 52);
    const manifest = await this.buildManifest(snapshot, remote, client, progress);
    LibraryStore.save(this.context, snapshot);
    const output = new util.TextEncoder().encodeInto(JSON.stringify(manifest));
    if (remoteBytes !== undefined) {
      await client.putAtomic(`${SYNC_ROOT}history/previous-manifest.json`, remoteBytes);
    }
    this.progress(progress, '发布同步清单', 92);
    await client.putAtomic(MANIFEST_PATH, output, etag);
    config.lastSyncAt = Date.now();
    config.lastStatus = '同步完成';
    config.enabled = true;
    this.saveConfig(config);
    this.progress(progress, '同步完成', 100);
    snapshot = LibraryStore.load(this.context);
    return snapshot;
  }

  private async mergeRemote(snapshot: LibrarySnapshot, manifest: SyncManifest, client: WebDavClient,
    progress?: WebDavProgress): Promise<void> {
    this.mergeAndApplyTombstones(snapshot, manifest.tombstones);
    if (manifest.readerSettings !== undefined && manifest.readerSettings.updatedAt > snapshot.settingsUpdatedAt) {
      snapshot.settings.textSize = manifest.readerSettings.textSizeSp;
      snapshot.settings.lineHeight = manifest.readerSettings.lineSpacingMultiplier;
      snapshot.settings.themeMode = manifest.readerSettings.themeMode;
      snapshot.settings.firstLineIndent = manifest.readerSettings.firstLineIndentEm;
      snapshot.settings.pageMargin = manifest.readerSettings.pageMarginDp;
      snapshot.settings.readMode = 1;
      snapshot.settingsUpdatedAt = manifest.readerSettings.updatedAt;
    }
    if (manifest.profile !== undefined && manifest.profile.nameUpdatedAt > snapshot.profileUpdatedAt) {
      snapshot.userName = manifest.profile.name;
      snapshot.profileUpdatedAt = manifest.profile.nameUpdatedAt;
    }
    for (let index = 0; index < manifest.books.length; index++) {
      const remote = manifest.books[index];
      if (this.isDeleted(snapshot, 'book', remote.syncId, remote.updatedAt)) {
        continue;
      }
      let local = snapshot.books.find((book: BookRecord): boolean => book.syncId === remote.syncId);
      if (local === undefined) {
        local = snapshot.books.find((book: BookRecord): boolean => book.title.trim() === remote.title.trim() &&
          book.author.trim() === remote.author.trim());
      }
      if (local === undefined) {
        this.progress(progress, `恢复书籍 ${remote.title}`, 20 + Math.min(28, index * 28 / Math.max(1, manifest.books.length)));
        local = await this.restoreRemoteBook(remote, client);
        snapshot.books.push(local);
      } else if (remote.updatedAt >= local.syncUpdatedAt) {
        const previousContentHash = local.syncContentHash;
        local.syncId = remote.syncId;
        this.applyRemoteBook(remote, local);
        if (remote.contentHash.length > 0 && previousContentHash !== remote.contentHash) {
          await this.replaceBookPayload(local, remote, client);
        }
      } else if (local.syncId !== remote.syncId) {
        // Same-title books created independently on Android and HarmonyOS become one shared entity.
        local.syncId = remote.syncId;
        local.syncUpdatedAt = Math.max(local.updatedAt, Date.now());
        local.syncContentHash = '';
      }
    }
    this.mergeRemoteBookmarks(snapshot, manifest.bookmarks);
    this.mergeRemoteNotes(snapshot, manifest.notes);
    this.mergeRemoteReading(snapshot, manifest.readingEvents);
  }

  private async buildManifest(snapshot: LibrarySnapshot, previous: SyncManifest, client: WebDavClient,
    progress?: WebDavProgress): Promise<SyncManifest> {
    const manifest = new SyncManifest();
    manifest.deviceId = snapshot.syncDeviceId;
    manifest.updatedAt = Date.now();
    manifest.profile.name = snapshot.userName;
    manifest.profile.nameUpdatedAt = snapshot.profileUpdatedAt;
    manifest.profile.avatarHash = previous.profile.avatarHash;
    manifest.profile.avatarUpdatedAt = previous.profile.avatarUpdatedAt;
    manifest.readerSettings.updatedAt = snapshot.settingsUpdatedAt;
    manifest.readerSettings.textSizeSp = snapshot.settings.textSize;
    manifest.readerSettings.lineSpacingMultiplier = snapshot.settings.lineHeight;
    manifest.readerSettings.themeMode = snapshot.settings.themeMode;
    manifest.readerSettings.readMode = previous.readerSettings.updatedAt > 0 ? previous.readerSettings.readMode : 1;
    manifest.readerSettings.fontMode = previous.readerSettings.fontMode;
    manifest.readerSettings.paragraphSpacingDp = previous.readerSettings.paragraphSpacingDp;
    manifest.readerSettings.firstLineIndentEm = snapshot.settings.firstLineIndent;
    manifest.readerSettings.pageMarginDp = snapshot.settings.pageMargin;
    manifest.readerSettings.pageTurnMode = previous.readerSettings.pageTurnMode;
    manifest.tombstones = this.mergedTombstones(previous.tombstones, snapshot.syncTombstones);
    manifest.folders = previous.folders;
    for (let index = 0; index < snapshot.books.length; index++) {
      const book = snapshot.books[index];
      if (book.syncContentHash.length === 0 || !(await client.exists(`${SYNC_ROOT}objects/${book.syncContentHash}.zip`))) {
        const archive = await this.createArchive(book);
        if (!(await client.exists(`${SYNC_ROOT}objects/${archive.sha256}.zip`))) {
          await client.putAtomic(`${SYNC_ROOT}objects/${archive.sha256}.zip`, this.readBytes(archive.path));
        }
        book.syncContentHash = archive.sha256;
        this.deleteRecursively(archive.path);
      }
      manifest.books.push(this.bookToSync(book));
      this.progress(progress, `上传书籍 ${index + 1}/${snapshot.books.length}`,
        52 + Math.min(34, (index + 1) * 34 / Math.max(1, snapshot.books.length)));
    }
    snapshot.bookmarks.forEach((bookmark: BookmarkRecord): void => {
      const book = snapshot.books.find((item: BookRecord): boolean => item.id === bookmark.bookId);
      if (book !== undefined) {
        manifest.bookmarks.push(this.bookmarkToSync(bookmark, book.syncId));
      }
    });
    snapshot.notes.forEach((note: NoteRecord): void => {
      const book = snapshot.books.find((item: BookRecord): boolean => item.id === note.bookId);
      if (book !== undefined) {
        manifest.notes.push(this.noteToSync(note, book));
      }
    });
    snapshot.dailyReading.forEach((daily: DailyReadingRecord): void => {
      const event = new SyncReadingEvent();
      event.syncId = daily.syncId;
      event.date = daily.date;
      event.readingMillis = daily.readingMillis;
      event.createdAt = daily.createdAt;
      manifest.readingEvents.push(event);
    });
    return manifest;
  }

  private async createArchive(book: BookRecord): Promise<ArchiveResult> {
    const root = `${this.context.cacheDir}/sync-${WebDavSyncService.uuid()}`;
    LibraryStore.ensureDirectory(root);
    const meta = new ArchiveMeta();
    const chapters = LibraryStore.loadChapters(book);
    chapters.forEach((chapter: ChapterRecord, index: number): void => {
      const directory = `${root}/payload/chapters/${index.toString().padStart(5, '0')}`;
      LibraryStore.ensureDirectory(directory);
      const relative = `payload/chapters/${index.toString().padStart(5, '0')}/chapter.txt`;
      this.writeText(`${root}/${relative}`, chapter.content);
      const item = new ArchiveChapterMeta();
      item.index = index;
      item.title = chapter.title;
      item.path = relative;
      meta.chapters.push(item);
    });
    this.writeText(`${root}/book.json`, JSON.stringify(meta));
    const zipPath = `${this.context.cacheDir}/book-${WebDavSyncService.uuid()}.zip`;
    const options: zlib.Options = {};
    await zlib.compressFile(root, zipPath, options);
    this.deleteRecursively(root);
    const output = new ArchiveResult();
    output.path = zipPath;
    output.sha256 = await hash.hash(zipPath, 'sha256');
    return output;
  }

  private async restoreRemoteBook(remote: SyncBook, client: WebDavClient): Promise<BookRecord> {
    const book = new BookRecord();
    book.id = `${Date.now()}_sync_${Math.floor(Math.random() * 100000)}`;
    book.syncId = remote.syncId;
    const directory = LibraryStore.bookDirectory(this.context, book.id);
    book.chapterFilePath = `${directory}/chapters.json`;
    this.applyRemoteBook(remote, book);
    await this.replaceBookPayload(book, remote, client);
    return book;
  }

  private async replaceBookPayload(book: BookRecord, remote: SyncBook, client: WebDavClient): Promise<void> {
    const bytes = await client.get(`${SYNC_ROOT}objects/${remote.contentHash}.zip`);
    if (bytes === undefined) {
      throw new Error(`服务器缺少书籍文件：${remote.title}`);
    }
    const zipPath = `${this.context.cacheDir}/restore-${WebDavSyncService.uuid()}.zip`;
    this.writeBytes(zipPath, bytes);
    const actualHash = await hash.hash(zipPath, 'sha256');
    if (actualHash.toLowerCase() !== remote.contentHash.toLowerCase()) {
      this.deleteRecursively(zipPath);
      throw new Error(`书籍文件校验失败：${remote.title}`);
    }
    const output = `${this.context.cacheDir}/restore-${WebDavSyncService.uuid()}`;
    LibraryStore.ensureDirectory(output);
    const options: zlib.Options = {};
    await zlib.decompressFile(zipPath, output, options);
    const metaPath = this.findFile(output, 'book.json');
    if (metaPath.length === 0) {
      throw new Error('同步书籍包缺少 book.json');
    }
    const meta = JSON.parse(fs.readTextSync(metaPath)) as ArchiveMeta;
    const archiveRoot = metaPath.substring(0, metaPath.length - 'book.json'.length);
    const chapters = new Array<ChapterRecord>();
    meta.chapters.sort((left: ArchiveChapterMeta, right: ArchiveChapterMeta): number => left.index - right.index)
      .forEach((item: ArchiveChapterMeta): void => {
        const path = `${archiveRoot}${item.path}`;
        if (!fs.accessSync(path)) {
          throw new Error('同步书籍包章节缺失');
        }
        chapters.push(new ChapterRecord(item.title, fs.readTextSync(path)));
      });
    LibraryStore.saveChapters(book.chapterFilePath, chapters);
    book.totalChapters = chapters.length;
    book.syncContentHash = remote.contentHash;
    this.deleteRecursively(zipPath);
    this.deleteRecursively(output);
  }

  private mergeRemoteBookmarks(snapshot: LibrarySnapshot, items: Array<SyncBookmark>): void {
    items.forEach((remote: SyncBookmark): void => {
      const book = snapshot.books.find((item: BookRecord): boolean => item.syncId === remote.bookSyncId);
      if (book === undefined) {
        return;
      }
      let local = snapshot.bookmarks.find((item: BookmarkRecord): boolean => item.syncId === remote.syncId);
      if (local !== undefined && local.updatedAt > remote.updatedAt) {
        return;
      }
      if (local === undefined) {
        local = new BookmarkRecord();
        local.id = `${Date.now()}_sync_bookmark_${snapshot.bookmarks.length}`;
        snapshot.bookmarks.push(local);
      }
      local.syncId = remote.syncId;
      local.bookId = book.id;
      local.chapterIndex = remote.chapterIndex;
      local.scrollOffset = remote.pageStartOffset;
      local.chapterTitle = remote.chapterTitle;
      local.summary = remote.summary;
      local.createdAt = remote.createdAt;
      local.updatedAt = remote.updatedAt;
    });
  }

  private mergeAndApplyTombstones(snapshot: LibrarySnapshot, remoteItems: Array<SyncTombstone>): void {
    remoteItems.forEach((remote: SyncTombstone): void => {
      const existing = snapshot.syncTombstones.find((item: SyncTombstoneRecord): boolean =>
        item.type === remote.type && item.syncId === remote.syncId);
      if (existing === undefined) {
        const item = new SyncTombstoneRecord();
        item.type = remote.type;
        item.syncId = remote.syncId;
        item.deletedAt = remote.deletedAt;
        snapshot.syncTombstones.push(item);
      } else if (remote.deletedAt > existing.deletedAt) {
        existing.deletedAt = remote.deletedAt;
      }
    });
    snapshot.syncTombstones.forEach((item: SyncTombstoneRecord): void => {
      if (item.type === 'book') {
        const removedIds = snapshot.books.filter((book: BookRecord): boolean => book.syncId === item.syncId)
          .map((book: BookRecord): string => book.id);
        snapshot.books = snapshot.books.filter((book: BookRecord): boolean => book.syncId !== item.syncId ||
          book.syncUpdatedAt > item.deletedAt);
        snapshot.bookmarks = snapshot.bookmarks.filter((bookmark: BookmarkRecord): boolean =>
          removedIds.indexOf(bookmark.bookId) < 0);
        snapshot.notes = snapshot.notes.filter((note: NoteRecord): boolean => removedIds.indexOf(note.bookId) < 0);
      } else if (item.type === 'bookmark') {
        snapshot.bookmarks = snapshot.bookmarks.filter((bookmark: BookmarkRecord): boolean =>
          bookmark.syncId !== item.syncId || bookmark.updatedAt > item.deletedAt);
      } else if (item.type === 'note') {
        snapshot.notes = snapshot.notes.filter((note: NoteRecord): boolean =>
          note.syncId !== item.syncId || note.updatedAt > item.deletedAt);
      }
    });
  }

  private mergedTombstones(remoteItems: Array<SyncTombstone>, localItems: Array<SyncTombstoneRecord>): Array<SyncTombstone> {
    const output = remoteItems.slice();
    localItems.forEach((local: SyncTombstoneRecord): void => {
      const existing = output.find((item: SyncTombstone): boolean => item.type === local.type && item.syncId === local.syncId);
      if (existing === undefined) {
        const item = new SyncTombstone();
        item.type = local.type;
        item.syncId = local.syncId;
        item.deletedAt = local.deletedAt;
        output.push(item);
      } else if (local.deletedAt > existing.deletedAt) {
        existing.deletedAt = local.deletedAt;
      }
    });
    return output;
  }

  private isDeleted(snapshot: LibrarySnapshot, type: string, syncId: string, changedAt: number): boolean {
    const tombstone = snapshot.syncTombstones.find((item: SyncTombstoneRecord): boolean =>
      item.type === type && item.syncId === syncId);
    return tombstone !== undefined && tombstone.deletedAt >= changedAt;
  }

  private mergeRemoteNotes(snapshot: LibrarySnapshot, items: Array<SyncNote>): void {
    items.forEach((remote: SyncNote): void => {
      const book = snapshot.books.find((item: BookRecord): boolean => item.syncId === remote.bookSyncId);
      if (book === undefined) {
        return;
      }
      let local = snapshot.notes.find((item: NoteRecord): boolean => item.syncId === remote.syncId);
      if (local !== undefined && local.updatedAt > remote.updatedAt) {
        return;
      }
      if (local === undefined) {
        local = new NoteRecord();
        local.id = `${Date.now()}_sync_note_${snapshot.notes.length}`;
        snapshot.notes.push(local);
      }
      local.syncId = remote.syncId;
      local.bookId = book.id;
      local.chapterIndex = remote.chapterIndex;
      local.paragraphIndex = 0;
      local.selectedText = remote.selectedText;
      local.noteText = remote.noteText;
      local.color = this.androidColorToHex(remote.color);
      local.createdAt = remote.createdAt;
      local.updatedAt = remote.updatedAt;
      const chapters = LibraryStore.loadChapters(book);
      if (remote.chapterIndex >= 0 && remote.chapterIndex < chapters.length && remote.selectedText.length > 0) {
        const paragraphs = chapters[remote.chapterIndex].content.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
          .split(/\n+/).map((value: string): string => value.trim()).filter((value: string): boolean => value.length > 0);
        for (let index = 0; index < paragraphs.length; index++) {
          const start = paragraphs[index].indexOf(remote.selectedText);
          if (start >= 0) {
            local.paragraphIndex = index;
            local.textStartOffset = start;
            local.textEndOffset = start + remote.selectedText.length;
            break;
          }
        }
      }
    });
  }

  private mergeRemoteReading(snapshot: LibrarySnapshot, events: Array<SyncReadingEvent>): void {
    events.forEach((event: SyncReadingEvent): void => {
      if (snapshot.dailyReading.some((item: DailyReadingRecord): boolean => item.syncId === event.syncId)) {
        return;
      }
      const existing = snapshot.dailyReading.find((item: DailyReadingRecord): boolean => item.date === event.date && item.syncId.length === 0);
      if (existing !== undefined) {
        existing.syncId = event.syncId;
        existing.readingMillis = Math.max(existing.readingMillis, event.readingMillis);
        existing.createdAt = event.createdAt;
      } else {
        const daily = new DailyReadingRecord(event.date, event.readingMillis);
        daily.syncId = event.syncId;
        daily.createdAt = event.createdAt;
        snapshot.dailyReading.push(daily);
      }
    });
  }

  private prepareLocal(snapshot: LibrarySnapshot, initializeMetadata: boolean): void {
    const now = Date.now();
    if (snapshot.syncDeviceId.length === 0) {
      snapshot.syncDeviceId = WebDavSyncService.uuid();
    }
    if (snapshot.profileUpdatedAt === 0 && initializeMetadata) {
      snapshot.profileUpdatedAt = now;
    }
    if (snapshot.settingsUpdatedAt === 0 && initializeMetadata) {
      snapshot.settingsUpdatedAt = now;
    }
    if (snapshot.syncTombstones === undefined) {
      snapshot.syncTombstones = new Array<SyncTombstoneRecord>();
    }
    snapshot.books.forEach((book: BookRecord): void => {
      if (book.syncId === undefined || book.syncId.length === 0) {
        book.syncId = WebDavSyncService.uuid();
      }
      if (book.syncContentHash === undefined) {
        book.syncContentHash = '';
      }
      if (book.syncUpdatedAt === undefined || book.syncUpdatedAt === 0) {
        book.syncUpdatedAt = book.updatedAt > 0 ? book.updatedAt : now;
      }
    });
    snapshot.bookmarks.forEach((bookmark: BookmarkRecord): void => {
      if (bookmark.syncId === undefined || bookmark.syncId.length === 0) {
        bookmark.syncId = WebDavSyncService.uuid();
      }
      if (bookmark.updatedAt === undefined || bookmark.updatedAt === 0) {
        bookmark.updatedAt = bookmark.createdAt > 0 ? bookmark.createdAt : now;
      }
    });
    snapshot.notes.forEach((note: NoteRecord): void => {
      if (note.syncId === undefined || note.syncId.length === 0) {
        note.syncId = WebDavSyncService.uuid();
      }
    });
    snapshot.dailyReading.forEach((daily: DailyReadingRecord): void => {
      if (daily.syncId === undefined || daily.syncId.length === 0) {
        daily.syncId = WebDavSyncService.uuid();
      }
      if (daily.createdAt === undefined || daily.createdAt === 0) {
        daily.createdAt = now;
      }
    });
  }

  private applyRemoteBook(remote: SyncBook, local: BookRecord): void {
    local.title = remote.title;
    local.author = remote.author;
    local.fileType = remote.fileType;
    local.category = remote.category;
    local.description = remote.description;
    local.totalChapters = remote.totalChapters;
    local.currentChapterIndex = remote.currentChapterIndex;
    local.scrollOffset = remote.scrollY;
    local.currentPageIndex = remote.currentPageIndex;
    local.pinnedAt = remote.pinnedAt;
    local.finishedAt = remote.finishedAt;
    local.createdAt = remote.createdAt;
    local.updatedAt = remote.updatedAt;
    local.syncUpdatedAt = remote.updatedAt;
    local.syncContentHash = remote.contentHash;
  }

  private bookToSync(book: BookRecord): SyncBook {
    const item = new SyncBook();
    item.syncId = book.syncId;
    item.contentHash = book.syncContentHash;
    item.updatedAt = book.syncUpdatedAt;
    item.title = book.title;
    item.author = book.author;
    item.fileType = book.fileType;
    item.category = book.category;
    item.description = book.description;
    item.totalChapters = book.totalChapters;
    item.currentChapterIndex = book.currentChapterIndex;
    item.scrollY = Math.floor(book.scrollOffset);
    item.currentPageIndex = book.currentPageIndex;
    item.currentPageStartOffset = 0;
    item.pinnedAt = book.pinnedAt;
    item.finishedAt = book.finishedAt;
    item.createdAt = book.createdAt;
    return item;
  }

  private bookmarkToSync(bookmark: BookmarkRecord, bookSyncId: string): SyncBookmark {
    const item = new SyncBookmark();
    item.syncId = bookmark.syncId;
    item.bookSyncId = bookSyncId;
    item.chapterIndex = bookmark.chapterIndex;
    item.pageStartOffset = Math.floor(bookmark.scrollOffset);
    item.chapterTitle = bookmark.chapterTitle;
    item.summary = bookmark.summary;
    item.createdAt = bookmark.createdAt;
    item.updatedAt = bookmark.updatedAt;
    return item;
  }

  private noteToSync(note: NoteRecord, book: BookRecord): SyncNote {
    const item = new SyncNote();
    item.syncId = note.syncId;
    item.bookSyncId = book.syncId;
    item.chapterIndex = note.chapterIndex;
    item.pageStartOffset = Math.max(0, note.textStartOffset);
    item.selectedText = note.selectedText;
    item.noteText = note.noteText;
    item.color = this.hexToAndroidColor(note.color);
    const chapters = LibraryStore.loadChapters(book);
    if (note.chapterIndex >= 0 && note.chapterIndex < chapters.length) {
      item.chapterTitle = chapters[note.chapterIndex].title;
    }
    item.createdAt = note.createdAt;
    item.updatedAt = note.updatedAt;
    return item;
  }

  private normalizeManifest(manifest: SyncManifest): void {
    if (manifest.books === undefined) manifest.books = new Array<SyncBook>();
    if (manifest.bookmarks === undefined) manifest.bookmarks = new Array<SyncBookmark>();
    if (manifest.notes === undefined) manifest.notes = new Array<SyncNote>();
    if (manifest.folders === undefined) manifest.folders = new Array<SyncFolder>();
    if (manifest.readingEvents === undefined) manifest.readingEvents = new Array<SyncReadingEvent>();
    if (manifest.tombstones === undefined) manifest.tombstones = new Array<SyncTombstone>();
    if (manifest.profile === undefined) manifest.profile = new SyncProfile();
    if (manifest.readerSettings === undefined) manifest.readerSettings = new SyncReaderSettings();
  }

  private validateConfig(config: WebDavConfig): void {
    if (!/^https?:\/\//i.test(config.url.trim())) {
      throw new Error('请输入完整的 http:// 或 https:// WebDAV 地址');
    }
    if (config.username.trim().length === 0 || config.password.length === 0) {
      throw new Error('请输入用户名和应用密码');
    }
  }

  private configPath(): string {
    const root = `${this.context.filesDir}/novelreader`;
    LibraryStore.ensureDirectory(root);
    return `${root}/${CONFIG_FILE}`;
  }

  private readBytes(path: string): Uint8Array {
    const stat = fs.statSync(path);
    const buffer = new ArrayBuffer(stat.size);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const length = fs.readSync(file.fd, buffer);
      return new Uint8Array(buffer, 0, length);
    } finally {
      fs.closeSync(file);
    }
  }

  private writeBytes(path: string, bytes: Uint8Array): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes.buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  private writeText(path: string, value: string): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, value);
    } finally {
      fs.closeSync(file);
    }
  }

  private findFile(root: string, name: string): string {
    const files = fs.listFileSync(root);
    for (let index = 0; index < files.length; index++) {
      const path = `${root}/${files[index]}`;
      const stat = fs.statSync(path);
      if (stat.isFile() && files[index] === name) {
        return path;
      }
      if (stat.isDirectory()) {
        const found = this.findFile(path, name);
        if (found.length > 0) {
          return found;
        }
      }
    }
    return '';
  }

  private deleteRecursively(path: string): void {
    try {
      const stat = fs.statSync(path);
      if (stat.isDirectory()) {
        fs.listFileSync(path).forEach((name: string): void => this.deleteRecursively(`${path}/${name}`));
        fs.rmdirSync(path);
      } else {
        fs.unlinkSync(path);
      }
    } catch (error) {
      // Cache cleanup is best effort.
    }
  }

  private androidColorToHex(value: number): string {
    const rgb = (value >>> 0).toString(16).padStart(8, '0').substring(2).toUpperCase();
    return `#${rgb}`;
  }

  private hexToAndroidColor(value: string): number {
    const clean = value.replace('#', '');
    const rgb = clean.length >= 6 ? clean.substring(clean.length - 6) : 'FFE08A';
    return parseInt(`66${rgb}`, 16);
  }

  private progress(callback: WebDavProgress | undefined, message: string, percent: number): void {
    if (callback !== undefined) {
      callback(message, Math.round(percent));
    }
  }

  static uuid(): string {
    const template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx';
    return template.replace(/[xy]/g, (character: string): string => {
      const random = Math.floor(Math.random() * 16);
      const value = character === 'x' ? random : (random & 0x3) | 0x8;
      return value.toString(16);
    });
  }
}
