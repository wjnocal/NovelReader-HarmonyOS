export class ChapterRecord {
  title: string = '';
  content: string = '';

  constructor(title: string = '', content: string = '') {
    this.title = title;
    this.content = content;
  }
}

export class BookRecord {
  id: string = '';
  title: string = '';
  author: string = '';
  fileType: string = '';
  category: string = '未分类';
  description: string = '';
  originalFilePath: string = '';
  chapterFilePath: string = '';
  totalChapters: number = 0;
  currentChapterIndex: number = 0;
  currentPageIndex: number = 0;
  scrollOffset: number = 0;
  pinnedAt: number = 0;
  finishedAt: number = 0;
  createdAt: number = 0;
  updatedAt: number = 0;
  syncId: string = '';
  syncContentHash: string = '';
  syncUpdatedAt: number = 0;
}

export class BookmarkRecord {
  id: string = '';
  bookId: string = '';
  chapterIndex: number = 0;
  pageIndex: number = 0;
  scrollOffset: number = 0;
  chapterTitle: string = '';
  summary: string = '';
  createdAt: number = 0;
  syncId: string = '';
  updatedAt: number = 0;
}

export class NoteRecord {
  id: string = '';
  bookId: string = '';
  chapterIndex: number = 0;
  paragraphIndex: number = 0;
  selectedText: string = '';
  noteText: string = '';
  color: string = '#DDAA43';
  textStartOffset: number = -1;
  textEndOffset: number = -1;
  createdAt: number = 0;
  updatedAt: number = 0;
  syncId: string = '';
}

export class ReaderSettings {
  textSize: number = 19;
  lineHeight: number = 1.65;
  themeMode: number = 0;
  firstLineIndent: number = 2;
  pageMargin: number = 22;
  readMode: number = 1;
}

export class DailyReadingRecord {
  date: string = '';
  readingMillis: number = 0;
  syncId: string = '';
  createdAt: number = 0;

  constructor(date: string = '', readingMillis: number = 0) {
    this.date = date;
    this.readingMillis = readingMillis;
  }
}

export class SyncTombstoneRecord {
  type: string = '';
  syncId: string = '';
  deletedAt: number = 0;
}

export class LibrarySnapshot {
  books: Array<BookRecord> = new Array<BookRecord>();
  bookmarks: Array<BookmarkRecord> = new Array<BookmarkRecord>();
  notes: Array<NoteRecord> = new Array<NoteRecord>();
  settings: ReaderSettings = new ReaderSettings();
  dailyReading: Array<DailyReadingRecord> = new Array<DailyReadingRecord>();
  readingGoalMinutes: number = 30;
  bookshelfBackgroundOpacity: number = 0.32;
  bookshelfGridMode: boolean = true;
  bookshelfSortMode: number = 0;
  userName: string = '默认用户';
  syncDeviceId: string = '';
  profileUpdatedAt: number = 0;
  settingsUpdatedAt: number = 0;
  syncTombstones: Array<SyncTombstoneRecord> = new Array<SyncTombstoneRecord>();
}

export class OnlineBookResult {
  sourceId: string = '';
  sourceName: string = '';
  bookName: string = '';
  author: string = '';
  category: string = '';
  latestChapter: string = '';
  lastUpdateTime: string = '';
  status: string = '';
  url: string = '';
}

export class OnlineSourceInfo {
  id: string = '';
  name: string = '';
  baseUrl: string = '';
  enabled: boolean = true;
  searchable: boolean = true;
  needProxy: boolean = false;
  comment: string = '';
  concurrency: number = 1;
}

export class OnlineExtractionRule {
  sourceId: string = '';
  sourceName: string = '通用网页';
  titleSelector: string = '';
  contentSelector: string = '';
  filterPattern: string = '';
  nextPageSelector: string = '';
  nextChapterPattern: string = '';
}

export class OnlineBookGroup {
  title: string = '';
  author: string = '';
  score: number = 0;
  versions: Array<OnlineBookResult> = new Array<OnlineBookResult>();
}

export class OnlineDownloadProgress {
  message: string = '';
  completed: number = 0;
  total: number = 0;
}

export class WebDavConfig {
  url: string = '';
  username: string = '';
  password: string = '';
  enabled: boolean = false;
  lastSyncAt: number = 0;
  lastStatus: string = '';
}

export class BackupBookRecord {
  book: BookRecord = new BookRecord();
  chapters: Array<ChapterRecord> = new Array<ChapterRecord>();
}

export class BackupDocument {
  version: number = 1;
  exportedAt: number = 0;
  books: Array<BackupBookRecord> = new Array<BackupBookRecord>();
  bookmarks: Array<BookmarkRecord> = new Array<BookmarkRecord>();
  notes: Array<NoteRecord> = new Array<NoteRecord>();
  settings: ReaderSettings = new ReaderSettings();
  dailyReading: Array<DailyReadingRecord> = new Array<DailyReadingRecord>();
  readingGoalMinutes: number = 30;
  bookshelfBackgroundOpacity: number = 0.32;
  bookshelfGridMode: boolean = true;
  bookshelfSortMode: number = 0;
  userName: string = '默认用户';
}

export class ParsedBook {
  title: string = '';
  author: string = '';
  description: string = '';
  fileType: string = '';
  chapters: Array<ChapterRecord> = new Array<ChapterRecord>();
}

export class ImportResult {
  books: Array<BookRecord> = new Array<BookRecord>();
  updatedCount: number = 0;
  errors: Array<string> = new Array<string>();
}
