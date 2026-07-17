import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  BackupBookRecord,
  BackupDocument,
  BookRecord,
  BookmarkRecord,
  ChapterRecord,
  LibrarySnapshot,
  NoteRecord
} from '../model/Models';
import { LibraryStore } from './LibraryStore';

export class BackupService {
  static async exportBackup(context: common.UIAbilityContext, snapshot: LibrarySnapshot): Promise<void> {
    const document = new BackupDocument();
    document.exportedAt = Date.now();
    document.settings = snapshot.settings;
    document.dailyReading = snapshot.dailyReading;
    document.readingGoalMinutes = snapshot.readingGoalMinutes;
    document.bookshelfBackgroundOpacity = snapshot.bookshelfBackgroundOpacity;
    document.userName = snapshot.userName;
    document.bookmarks = snapshot.bookmarks;
    document.notes = snapshot.notes;
    snapshot.books.forEach((book: BookRecord) => {
      const item = new BackupBookRecord();
      item.book = book;
      item.chapters = LibraryStore.loadChapters(book);
      document.books.push(item);
    });

    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`NovelReader-backup-${BackupService.dateName()}.json`];
    options.fileSuffixChoices = ['JSON 备份|.json'];
    const uris = await new picker.DocumentViewPicker(context).save(options);
    if (uris.length === 0) {
      throw new Error('未选择保存位置');
    }
    const file = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, JSON.stringify(document));
    } finally {
      fs.closeSync(file);
    }
  }

  static async importBackup(context: common.UIAbilityContext): Promise<number> {
    const options = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = ['NovelReader 备份|.json'];
    options.maxSelectNumber = 1;
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) {
      throw new Error('未选择备份文件');
    }
    const document = JSON.parse(BackupService.readUriText(uris[0])) as BackupDocument;
    if (document.version !== 1 || document.books === undefined) {
      throw new Error('不支持的备份格式');
    }

    const snapshot = LibraryStore.load(context);
    const idMap = new Map<string, string>();
    let restored = 0;
    document.books.forEach((item: BackupBookRecord, index: number) => {
      const duplicated = snapshot.books.some((existing: BookRecord) => existing.title === item.book.title &&
        existing.author === item.book.author);
      if (duplicated) {
        return;
      }
      const newId = `${Date.now()}_restore_${index}`;
      const directory = LibraryStore.bookDirectory(context, newId);
      const book = BackupService.copyBook(item.book);
      idMap.set(item.book.id, newId);
      book.id = newId;
      book.originalFilePath = '';
      book.chapterFilePath = `${directory}/chapters.json`;
      book.totalChapters = item.chapters.length;
      book.updatedAt = Date.now();
      LibraryStore.saveChapters(book.chapterFilePath, item.chapters);
      snapshot.books.push(book);
      restored++;
    });

    if (document.bookmarks !== undefined) {
      document.bookmarks.forEach((source: BookmarkRecord) => {
        const newBookId = idMap.get(source.bookId);
        if (newBookId !== undefined) {
          const bookmark = BackupService.copyBookmark(source);
          bookmark.id = `${Date.now()}_bookmark_${snapshot.bookmarks.length}`;
          bookmark.bookId = newBookId;
          snapshot.bookmarks.push(bookmark);
        }
      });
    }
    if (document.notes !== undefined) {
      document.notes.forEach((source: NoteRecord) => {
        const newBookId = idMap.get(source.bookId);
        if (newBookId !== undefined) {
          const note = BackupService.copyNote(source);
          note.id = `${Date.now()}_note_${snapshot.notes.length}`;
          note.bookId = newBookId;
          snapshot.notes.push(note);
        }
      });
    }
    if (document.settings !== undefined) {
      snapshot.settings = document.settings;
    }
    if (document.dailyReading !== undefined) {
      snapshot.dailyReading = document.dailyReading;
    }
    if (document.readingGoalMinutes > 0) {
      snapshot.readingGoalMinutes = document.readingGoalMinutes;
    }
    if (document.bookshelfBackgroundOpacity >= 0.15 && document.bookshelfBackgroundOpacity <= 0.95) {
      snapshot.bookshelfBackgroundOpacity = document.bookshelfBackgroundOpacity;
    }
    if (document.userName !== undefined && document.userName.trim().length > 0) {
      snapshot.userName = document.userName;
    }
    LibraryStore.save(context, snapshot);
    return restored;
  }

  private static readUriText(uri: string): string {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      const length = fs.readSync(file.fd, buffer);
      return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer, 0, length));
    } finally {
      fs.closeSync(file);
    }
  }

  private static copyBook(source: BookRecord): BookRecord {
    const book = new BookRecord();
    book.id = source.id;
    book.title = source.title;
    book.author = source.author;
    book.fileType = source.fileType;
    book.category = source.category;
    book.description = source.description;
    book.originalFilePath = source.originalFilePath;
    book.chapterFilePath = source.chapterFilePath;
    book.totalChapters = source.totalChapters;
    book.currentChapterIndex = source.currentChapterIndex;
    book.currentPageIndex = source.currentPageIndex;
    book.scrollOffset = source.scrollOffset;
    book.pinnedAt = source.pinnedAt;
    book.finishedAt = source.finishedAt;
    book.createdAt = source.createdAt;
    book.updatedAt = source.updatedAt;
    return book;
  }

  private static copyBookmark(source: BookmarkRecord): BookmarkRecord {
    const bookmark = new BookmarkRecord();
    bookmark.id = source.id;
    bookmark.bookId = source.bookId;
    bookmark.chapterIndex = source.chapterIndex;
    bookmark.scrollOffset = source.scrollOffset;
    bookmark.chapterTitle = source.chapterTitle;
    bookmark.summary = source.summary;
    bookmark.createdAt = source.createdAt;
    return bookmark;
  }

  private static copyNote(source: NoteRecord): NoteRecord {
    const note = new NoteRecord();
    note.id = source.id;
    note.bookId = source.bookId;
    note.chapterIndex = source.chapterIndex;
    note.paragraphIndex = source.paragraphIndex;
    note.selectedText = source.selectedText;
    note.noteText = source.noteText;
    note.color = source.color;
    note.createdAt = source.createdAt;
    note.updatedAt = source.updatedAt;
    return note;
  }

  private static dateName(): string {
    const date = new Date();
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }
}
