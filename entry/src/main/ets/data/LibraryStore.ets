import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BookRecord, ChapterRecord, DailyReadingRecord, LibrarySnapshot, NoteRecord, ReaderSettings } from '../model/Models';

const LIBRARY_FILE = 'library.json';

export class LibraryStore {
  static load(context: common.UIAbilityContext): LibrarySnapshot {
    const root = LibraryStore.rootDir(context);
    LibraryStore.ensureDirectory(root);
    const path = `${root}/${LIBRARY_FILE}`;
    let snapshot = LibraryStore.readSnapshot(path);
    if (snapshot === undefined) {
      // A previous known-good copy protects the bookshelf from interrupted writes or malformed JSON.
      snapshot = LibraryStore.readSnapshot(`${path}.bak`);
    }
    return snapshot === undefined ? new LibrarySnapshot() : LibraryStore.normalizeSnapshot(snapshot);
  }

  static save(context: common.UIAbilityContext, snapshot: LibrarySnapshot): void {
    const root = LibraryStore.rootDir(context);
    LibraryStore.ensureDirectory(root);
    LibraryStore.writeAtomic(`${root}/${LIBRARY_FILE}`, JSON.stringify(snapshot), true);
  }

  static normalizeSnapshot(snapshot: LibrarySnapshot): LibrarySnapshot {
    const defaults = new ReaderSettings();
    if (snapshot.books === undefined) {
      snapshot.books = new Array<BookRecord>();
    }
    snapshot.books.forEach((book: BookRecord): void => {
      if (book.id === undefined) book.id = '';
      if (book.title === undefined || book.title.trim().length === 0) book.title = '未命名书籍';
      if (book.author === undefined || book.author.trim().length === 0) book.author = '未知作者';
      if (book.fileType === undefined || book.fileType.length === 0) book.fileType = 'txt';
      if (book.category === undefined || book.category.trim().length === 0) book.category = '未分类';
      if (book.description === undefined) book.description = '';
      if (book.originalFilePath === undefined) book.originalFilePath = '';
      if (book.chapterFilePath === undefined) book.chapterFilePath = '';
      if (book.totalChapters === undefined || book.totalChapters < 0) book.totalChapters = 0;
      if (book.currentChapterIndex === undefined || book.currentChapterIndex < 0) book.currentChapterIndex = 0;
      if (book.totalChapters > 0 && book.currentChapterIndex >= book.totalChapters) {
        book.currentChapterIndex = book.totalChapters - 1;
      }
      if (book.currentPageIndex === undefined || book.currentPageIndex < 0) book.currentPageIndex = 0;
      if (book.scrollOffset === undefined || book.scrollOffset < 0) book.scrollOffset = 0;
      if (book.pinnedAt === undefined) book.pinnedAt = 0;
      if (book.finishedAt === undefined) book.finishedAt = 0;
      if (book.createdAt === undefined) book.createdAt = 0;
      if (book.updatedAt === undefined) book.updatedAt = book.createdAt;
      if (book.syncId === undefined) book.syncId = '';
      if (book.syncContentHash === undefined) book.syncContentHash = '';
      if (book.syncUpdatedAt === undefined) book.syncUpdatedAt = 0;
    });
    if (snapshot.bookmarks === undefined) snapshot.bookmarks = [];
    snapshot.bookmarks.forEach((bookmark): void => {
      if (bookmark.id === undefined) bookmark.id = '';
      if (bookmark.bookId === undefined) bookmark.bookId = '';
      if (bookmark.chapterIndex === undefined || bookmark.chapterIndex < 0) bookmark.chapterIndex = 0;
      if (bookmark.chapterTitle === undefined) bookmark.chapterTitle = '';
      if (bookmark.summary === undefined) bookmark.summary = '';
      if (bookmark.createdAt === undefined) bookmark.createdAt = 0;
      if (bookmark.pageIndex === undefined || bookmark.pageIndex < 0) bookmark.pageIndex = 0;
      if (bookmark.scrollOffset === undefined || bookmark.scrollOffset < 0) bookmark.scrollOffset = 0;
      if (bookmark.updatedAt === undefined) bookmark.updatedAt = bookmark.createdAt;
      if (bookmark.syncId === undefined) bookmark.syncId = '';
    });
    if (snapshot.notes === undefined) snapshot.notes = [];
    snapshot.notes.forEach((note: NoteRecord): void => {
      if (note.id === undefined) note.id = '';
      if (note.bookId === undefined) note.bookId = '';
      if (note.chapterIndex === undefined || note.chapterIndex < 0) note.chapterIndex = 0;
      if (note.paragraphIndex === undefined || note.paragraphIndex < 0) note.paragraphIndex = 0;
      if (note.selectedText === undefined) note.selectedText = '';
      if (note.noteText === undefined) note.noteText = '';
      if (note.createdAt === undefined) note.createdAt = 0;
      if (note.textStartOffset === undefined) note.textStartOffset = -1;
      if (note.textEndOffset === undefined) note.textEndOffset = -1;
      if (note.color === undefined || note.color.length === 0) note.color = '#DDAA43';
      if (note.updatedAt === undefined) note.updatedAt = note.createdAt;
      if (note.syncId === undefined) note.syncId = '';
    });
    if (snapshot.settings === undefined) snapshot.settings = defaults;
    if (snapshot.settings.textSize === undefined || snapshot.settings.textSize < 14 ||
      snapshot.settings.textSize > 32) snapshot.settings.textSize = defaults.textSize;
    if (snapshot.settings.lineHeight === undefined || snapshot.settings.lineHeight < 1.2 ||
      snapshot.settings.lineHeight > 2.2) snapshot.settings.lineHeight = defaults.lineHeight;
    if (snapshot.settings.themeMode === undefined || snapshot.settings.themeMode < 0 ||
      snapshot.settings.themeMode > 3) snapshot.settings.themeMode = defaults.themeMode;
    if (snapshot.settings.firstLineIndent === undefined) snapshot.settings.firstLineIndent = defaults.firstLineIndent;
    if (snapshot.settings.pageMargin === undefined || snapshot.settings.pageMargin < 8 ||
      snapshot.settings.pageMargin > 48) snapshot.settings.pageMargin = defaults.pageMargin;
    if (snapshot.settings.readMode !== 0 && snapshot.settings.readMode !== 1) {
      snapshot.settings.readMode = defaults.readMode;
    }
    if (snapshot.dailyReading === undefined) snapshot.dailyReading = new Array<DailyReadingRecord>();
    snapshot.dailyReading.forEach((daily: DailyReadingRecord): void => {
      if (daily.date === undefined) daily.date = '';
      if (daily.readingMillis === undefined || daily.readingMillis < 0) daily.readingMillis = 0;
      if (daily.syncId === undefined) daily.syncId = '';
      if (daily.createdAt === undefined) daily.createdAt = 0;
    });
    if (snapshot.syncTombstones === undefined) snapshot.syncTombstones = [];
    if (snapshot.syncDeviceId === undefined) snapshot.syncDeviceId = '';
    if (snapshot.profileUpdatedAt === undefined) snapshot.profileUpdatedAt = 0;
    if (snapshot.settingsUpdatedAt === undefined) snapshot.settingsUpdatedAt = 0;
    if (snapshot.readingGoalMinutes === undefined || snapshot.readingGoalMinutes <= 0) {
      snapshot.readingGoalMinutes = 30;
    }
    if (snapshot.bookshelfBackgroundOpacity === undefined || snapshot.bookshelfBackgroundOpacity < 0.15 ||
      snapshot.bookshelfBackgroundOpacity > 0.95) snapshot.bookshelfBackgroundOpacity = 0.32;
    if (snapshot.bookshelfGridMode === undefined) snapshot.bookshelfGridMode = true;
    if (snapshot.bookshelfSortMode === undefined || snapshot.bookshelfSortMode < 0 ||
      snapshot.bookshelfSortMode > 2) snapshot.bookshelfSortMode = 0;
    if (snapshot.userName === undefined || snapshot.userName.trim().length === 0) snapshot.userName = '默认用户';
    return snapshot;
  }

  static loadChapters(book: BookRecord): Array<ChapterRecord> {
    try {
      const json = fs.readTextSync(book.chapterFilePath);
      const chapters = JSON.parse(json) as Array<ChapterRecord>;
      if (!Array.isArray(chapters)) {
        return new Array<ChapterRecord>();
      }
      return chapters.filter((chapter: ChapterRecord): boolean => chapter !== undefined).map((chapter: ChapterRecord): ChapterRecord =>
        new ChapterRecord(chapter.title ?? '', chapter.content ?? ''));
    } catch (error) {
      return new Array<ChapterRecord>();
    }
  }

  static saveChapters(path: string, chapters: Array<ChapterRecord>): void {
    LibraryStore.writeAtomic(path, JSON.stringify(chapters));
  }

  static bookDirectory(context: common.UIAbilityContext, bookId: string): string {
    const path = `${LibraryStore.rootDir(context)}/books/${bookId}`;
    LibraryStore.ensureDirectory(path);
    return path;
  }

  static deleteBookFiles(context: common.UIAbilityContext, bookId: string): void {
    const path = `${LibraryStore.rootDir(context)}/books/${bookId}`;
    LibraryStore.deleteRecursively(path);
  }

  static ensureDirectory(path: string): void {
    let exists = false;
    try {
      exists = fs.accessSync(path);
    } catch (error) {
      exists = false;
    }
    if (!exists) {
      fs.mkdirSync(path, true);
    }
  }

  static deleteRecursively(path: string): void {
    try {
      const stat = fs.statSync(path);
      if (stat.isDirectory()) {
        const names = fs.listFileSync(path);
        names.forEach((name: string) => {
          LibraryStore.deleteRecursively(`${path}/${name}`);
        });
        fs.rmdirSync(path);
      } else {
        fs.unlinkSync(path);
      }
    } catch (error) {
      // Missing files do not make deleting a book fail.
    }
  }

  private static rootDir(context: common.UIAbilityContext): string {
    return `${context.filesDir}/novelreader`;
  }

  private static readSnapshot(path: string): LibrarySnapshot | undefined {
    try {
      const json = fs.readTextSync(path);
      return json.trim().length === 0 ? undefined : JSON.parse(json) as LibrarySnapshot;
    } catch (error) {
      return undefined;
    }
  }

  private static writeAtomic(path: string, content: string, keepBackup: boolean = false): void {
    const temporary = `${path}.tmp`;
    LibraryStore.writeText(temporary, content);
    if (keepBackup) {
      try {
        if (fs.accessSync(path)) fs.copyFileSync(path, `${path}.bak`);
      } catch (error) {
        // The first save has no previous copy.
      }
    }
    try {
      fs.renameSync(temporary, path);
    } catch (error) {
      // Some document providers do not replace an existing file on rename.
      LibraryStore.writeText(path, content);
      LibraryStore.deleteRecursively(temporary);
    }
  }

  private static writeText(path: string, content: string): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
  }
}
