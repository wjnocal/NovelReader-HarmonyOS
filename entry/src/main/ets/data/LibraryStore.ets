import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BookRecord, ChapterRecord, DailyReadingRecord, LibrarySnapshot, NoteRecord, ReaderSettings } from '../model/Models';

const LIBRARY_FILE = 'library.json';

export class LibraryStore {
  static load(context: common.UIAbilityContext): LibrarySnapshot {
    const root = LibraryStore.rootDir(context);
    LibraryStore.ensureDirectory(root);
    const path = `${root}/${LIBRARY_FILE}`;
    try {
      const json = fs.readTextSync(path);
      if (json.trim().length > 0) {
        const snapshot = JSON.parse(json) as LibrarySnapshot;
        if (snapshot.books === undefined) {
          snapshot.books = new Array<BookRecord>();
        }
        if (snapshot.bookmarks === undefined) {
          snapshot.bookmarks = [];
        }
        if (snapshot.notes === undefined) {
          snapshot.notes = [];
        }
        snapshot.notes.forEach((note: NoteRecord): void => {
          if (note.textStartOffset === undefined) {
            note.textStartOffset = -1;
          }
          if (note.textEndOffset === undefined) {
            note.textEndOffset = -1;
          }
        });
        if (snapshot.settings === undefined) {
          snapshot.settings = new ReaderSettings();
        }
        // Paged reading is temporarily disabled. Migrate every saved preference to scroll mode.
        snapshot.settings.readMode = 1;
        if (snapshot.dailyReading === undefined) {
          snapshot.dailyReading = new Array<DailyReadingRecord>();
        }
        if (snapshot.syncTombstones === undefined) {
          snapshot.syncTombstones = [];
        }
        if (snapshot.syncDeviceId === undefined) {
          snapshot.syncDeviceId = '';
        }
        if (snapshot.profileUpdatedAt === undefined) {
          snapshot.profileUpdatedAt = 0;
        }
        if (snapshot.settingsUpdatedAt === undefined) {
          snapshot.settingsUpdatedAt = 0;
        }
        if (snapshot.readingGoalMinutes === undefined || snapshot.readingGoalMinutes <= 0) {
          snapshot.readingGoalMinutes = 30;
        }
        if (snapshot.bookshelfBackgroundOpacity === undefined) {
          snapshot.bookshelfBackgroundOpacity = 0.32;
        }
        if (snapshot.userName === undefined || snapshot.userName.trim().length === 0) {
          snapshot.userName = '默认用户';
        }
        return snapshot;
      }
    } catch (error) {
      // The first launch has no library file yet. A clean snapshot is expected.
    }
    return new LibrarySnapshot();
  }

  static save(context: common.UIAbilityContext, snapshot: LibrarySnapshot): void {
    const root = LibraryStore.rootDir(context);
    LibraryStore.ensureDirectory(root);
    LibraryStore.writeText(`${root}/${LIBRARY_FILE}`, JSON.stringify(snapshot));
  }

  static loadChapters(book: BookRecord): Array<ChapterRecord> {
    try {
      const json = fs.readTextSync(book.chapterFilePath);
      return JSON.parse(json) as Array<ChapterRecord>;
    } catch (error) {
      return new Array<ChapterRecord>();
    }
  }

  static saveChapters(path: string, chapters: Array<ChapterRecord>): void {
    LibraryStore.writeText(path, JSON.stringify(chapters));
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

  private static writeText(path: string, content: string): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
  }
}
