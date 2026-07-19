import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LibraryStore } from '../data/LibraryStore';
import { BookRecord, ImportResult, ParsedBook } from '../model/Models';
import { EpubParser } from './EpubParser';
import { TxtParser } from './TxtParser';

export class BookImporter {
  static async selectAndImport(context: common.UIAbilityContext): Promise<ImportResult> {
    const options = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = ['电子书|.txt,.epub'];
    options.maxSelectNumber = 20;
    const viewPicker = new picker.DocumentViewPicker(context);
    const uris = await viewPicker.select(options);
    const result = new ImportResult();
    const snapshot = LibraryStore.load(context);

    for (let index = 0; index < uris.length; index++) {
      const uri = uris[index];
      const fileName = BookImporter.fileNameFromUri(uri);
      const extension = BookImporter.extensionOf(fileName);
      if (extension !== 'txt' && extension !== 'epub') {
        result.errors.push(`${fileName}：仅支持 TXT 和 EPUB`);
        continue;
      }

      const bookId = `${Date.now()}_${index}`;
      const bookDir = LibraryStore.bookDirectory(context, bookId);
      const originalPath = `${bookDir}/original.${extension}`;
      try {
        BookImporter.copyPickedFile(uri, originalPath);
        let parsed: ParsedBook;
        if (extension === 'txt') {
          const content = BookImporter.decodeTextFile(originalPath);
          parsed = TxtParser.parse(content, fileName);
        } else {
          parsed = await EpubParser.parse(originalPath, `${bookDir}/epub_extract`, fileName);
        }

        const existing = snapshot.books.find((item: BookRecord): boolean =>
          item.title.trim().toLowerCase() === parsed.title.trim().toLowerCase() &&
          item.author.trim().toLowerCase() === parsed.author.trim().toLowerCase() &&
          item.fileType === parsed.fileType);
        if (existing !== undefined) {
          BookImporter.updateExistingBook(context, existing, parsed, originalPath, extension);
          LibraryStore.deleteBookFiles(context, bookId);
          result.updatedCount++;
          continue;
        }

        const chapterFilePath = `${bookDir}/chapters.json`;
        LibraryStore.saveChapters(chapterFilePath, parsed.chapters);
        const now = Date.now();
        const book = new BookRecord();
        book.id = bookId;
        book.title = parsed.title;
        book.author = parsed.author;
        book.description = parsed.description;
        book.fileType = parsed.fileType;
        book.originalFilePath = originalPath;
        book.chapterFilePath = chapterFilePath;
        book.totalChapters = parsed.chapters.length;
        book.createdAt = now;
        book.updatedAt = now;
        snapshot.books.push(book);
        result.books.push(book);
      } catch (error) {
        LibraryStore.deleteBookFiles(context, bookId);
        result.errors.push(`${fileName}：${String(error)}`);
      }
    }

    snapshot.books.sort((left: BookRecord, right: BookRecord) => right.updatedAt - left.updatedAt);
    LibraryStore.save(context, snapshot);
    return result;
  }

  private static updateExistingBook(context: common.UIAbilityContext, book: BookRecord, parsed: ParsedBook,
    importedPath: string, extension: string): void {
    const directory = LibraryStore.bookDirectory(context, book.id);
    const chapterPath = book.chapterFilePath === undefined || book.chapterFilePath.length === 0 ?
      `${directory}/chapters.json` : book.chapterFilePath;
    const originalPath = `${directory}/original.${extension}`;
    fs.copyFileSync(importedPath, originalPath);
    LibraryStore.saveChapters(chapterPath, parsed.chapters);
    const now = Date.now();
    book.title = parsed.title;
    book.author = parsed.author;
    book.description = parsed.description;
    book.fileType = parsed.fileType;
    book.originalFilePath = originalPath;
    book.chapterFilePath = chapterPath;
    book.totalChapters = parsed.chapters.length;
    book.currentChapterIndex = Math.max(0, Math.min(book.currentChapterIndex, parsed.chapters.length - 1));
    book.currentPageIndex = 0;
    book.scrollOffset = 0;
    book.updatedAt = now;
    book.syncUpdatedAt = now;
    book.syncContentHash = '';
  }

  private static copyPickedFile(uri: string, destination: string): void {
    // Picker returns an authorized URI rather than an application sandbox path.
    // Open the URI first and copy by file descriptors so cloud/file-provider URIs work too.
    const source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const target = fs.openSync(destination,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(source.fd, target.fd);
      } finally {
        fs.closeSync(target);
      }
    } finally {
      fs.closeSync(source);
    }
  }

  private static decodeTextFile(path: string): string {
    const stat = fs.statSync(path);
    const buffer = new ArrayBuffer(stat.size);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    let readLength = 0;
    try {
      readLength = fs.readSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    const bytes = new Uint8Array(buffer, 0, readLength);
    const utf8 = util.TextDecoder.create('utf-8').decodeToString(bytes);
    const replacementCount = BookImporter.countReplacementCharacters(utf8);
    if (replacementCount * 200 <= Math.max(1, utf8.length)) {
      return utf8;
    }
    try {
      return util.TextDecoder.create('gb18030').decodeToString(bytes);
    } catch (error) {
      return utf8;
    }
  }

  private static countReplacementCharacters(text: string): number {
    let count = 0;
    for (let index = 0; index < text.length; index++) {
      if (text.charAt(index) === '\uFFFD') {
        count++;
      }
    }
    return count;
  }

  private static fileNameFromUri(uri: string): string {
    const cleanUri = uri.indexOf('?') >= 0 ? uri.substring(0, uri.indexOf('?')) : uri;
    const slash = cleanUri.lastIndexOf('/');
    const encoded = slash >= 0 ? cleanUri.substring(slash + 1) : cleanUri;
    try {
      return decodeURIComponent(encoded);
    } catch (error) {
      return encoded;
    }
  }

  private static extensionOf(name: string): string {
    const dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}
