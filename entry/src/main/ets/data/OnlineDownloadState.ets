import { ChapterRecord, BookRecord } from '../model/Models';

// Completed workers may finish out of order. Only a contiguous prefix is readable.
export class OnlineChapterPublisher {
  private pending: Map<number, ChapterRecord> = new Map<number, ChapterRecord>();
  private chapters: Array<ChapterRecord> = new Array<ChapterRecord>();

  complete(index: number, chapter: ChapterRecord): Array<ChapterRecord> {
    if (index < this.chapters.length || this.pending.has(index)) return [];
    this.pending.set(index, chapter);
    const appended = new Array<ChapterRecord>();
    while (this.pending.has(this.chapters.length)) {
      const next = this.pending.get(this.chapters.length)!;
      this.pending.delete(this.chapters.length);
      this.chapters.push(next);
      appended.push(next);
    }
    return appended;
  }

  readable(): Array<ChapterRecord> {
    return this.chapters.slice();
  }
}

export class OnlineDownloadState {
  static incomplete(book: BookRecord): boolean {
    return book.downloadComplete === false;
  }

  static applyMetadata(target: BookRecord, source: BookRecord): void {
    target.fileType = source.fileType;
    target.originalFilePath = source.originalFilePath;
    target.chapterFilePath = source.chapterFilePath;
    target.totalChapters = source.totalChapters;
    target.availableChapters = source.availableChapters;
    target.downloadKey = source.downloadKey;
    target.downloadComplete = source.downloadComplete;
    target.downloadRevision = source.downloadRevision;
    target.syncContentHash = source.syncContentHash;
  }

  static key(identity: string): string {
    let first = 2166136261;
    let second = 5381;
    for (let index = 0; index < identity.length; index++) {
      first = Math.imul(first ^ identity.charCodeAt(index), 16777619);
      second = Math.imul(second, 33) ^ identity.charCodeAt(index);
    }
    return `${(first >>> 0).toString(16)}-${(second >>> 0).toString(16)}`;
  }
}
