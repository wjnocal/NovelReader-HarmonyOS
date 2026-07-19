import { ChapterRecord, ParsedBook } from '../model/Models';

export enum ChapterSplitMode {
  DEFAULT = 0,
  CHINESE_CHAPTER = 1,
  ARABIC_CHAPTER = 2,
  ARABIC_MARK = 3,
  CHAPTER_ARABIC = 4,
  CHINESE_SECTION = 5,
  CHINESE_VOLUME = 6,
  PROLOGUE = 7
}

const CHINESE_NUMERAL = '一二三四五六七八九十百千万零〇两';

export class TxtParser {
  static parse(text: string, fallbackTitle: string,
    splitMode: ChapterSplitMode = ChapterSplitMode.DEFAULT): ParsedBook {
    const normalized = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim();
    if (normalized.length === 0) {
      throw new Error('TXT 文件内容为空');
    }
    const parsed = new ParsedBook();
    parsed.title = TxtParser.stripExtension(fallbackTitle);
    parsed.author = '本地 TXT';
    parsed.fileType = 'txt';

    const matcher = TxtParser.patternForMode(splitMode);
    let chapterStart = -1;
    let chapterTitle = '';
    let chapterNumber = 1;
    let match: RegExpExecArray | null = matcher.exec(normalized);

    while (match !== null) {
      if (chapterTitle.length > 0) {
        TxtParser.addChapter(parsed, chapterTitle,
          normalized.substring(chapterStart, match.index).trim(), chapterNumber++);
      } else if (match.index > 0) {
        const preface = normalized.substring(0, match.index).trim();
        if (preface.length > 0) {
          TxtParser.addChapter(parsed, '序章', preface, chapterNumber++);
        }
      }
      // The whole matching line is the chapter title. Body fragments never match.
      chapterTitle = match[1].trim();
      chapterStart = match.index + match[0].length;
      match = matcher.exec(normalized);
    }

    if (chapterTitle.length > 0) {
      TxtParser.addChapter(parsed, chapterTitle, normalized.substring(chapterStart).trim(), chapterNumber);
    }
    if (parsed.chapters.length === 0) {
      TxtParser.addChapter(parsed, parsed.title, normalized, 1);
    }
    return parsed;
  }

  static labelForMode(mode: ChapterSplitMode): string {
    switch (mode) {
      case ChapterSplitMode.CHINESE_CHAPTER:
        return '第X章（第一章）';
      case ChapterSplitMode.ARABIC_CHAPTER:
        return '第x章（第1章）';
      case ChapterSplitMode.ARABIC_MARK:
        return 'x、（1、）';
      case ChapterSplitMode.CHAPTER_ARABIC:
        return 'chapter x（chapter1）';
      case ChapterSplitMode.CHINESE_SECTION:
        return '第X节/第x节';
      case ChapterSplitMode.CHINESE_VOLUME:
        return '第X卷/第x卷';
      case ChapterSplitMode.PROLOGUE:
        return '序章/楔子/后记';
      default:
        return '默认（第X章/第x章）';
    }
  }

  private static patternForMode(mode: ChapterSplitMode): RegExp {
    const number = `\\d${CHINESE_NUMERAL}`;
    switch (mode) {
      case ChapterSplitMode.CHINESE_CHAPTER:
        return new RegExp(`^\\s*(第[${CHINESE_NUMERAL}]+章[^\\r\\n]*)\\s*$`, 'gm');
      case ChapterSplitMode.ARABIC_CHAPTER:
        return /^\s*(第\d+章[^\r\n]*)\s*$/gm;
      case ChapterSplitMode.ARABIC_MARK:
        return /^\s*(\d+、[^\r\n]*)\s*$/gm;
      case ChapterSplitMode.CHAPTER_ARABIC:
        return /^\s*((?:chapter|chap\.?|ch\.?)[\s.]*\d+[^\r\n]*)\s*$/gim;
      case ChapterSplitMode.CHINESE_SECTION:
        return new RegExp(`^\\s*(第[${number}]+节[^\\r\\n]*)\\s*$`, 'gm');
      case ChapterSplitMode.CHINESE_VOLUME:
        return new RegExp(`^\\s*(第[${number}]+卷[^\\r\\n]*)\\s*$`, 'gm');
      case ChapterSplitMode.PROLOGUE:
        return /^\s*((?:(?:序章|序言|楔子|引子|正文|后记)(?:[ \t　:：-]+[^\r\n]+)?|番外[^\r\n]*))\s*$/gm;
      default:
        // Automatic mode covers the chapter styles most commonly found in local novels.
        // Explicit modes remain available when a book uses ambiguous numbered headings.
        return new RegExp(
          `^\\s*((?:第[${number}]+(?:章|节|卷|部)[^\\r\\n]*|` +
          `(?:chapter|chap\\.?|ch\\.?)[\\s.]*\\d+[^\\r\\n]*|` +
          `(?:(?:序章|序言|楔子|引子|正文|后记)(?:[ \\t　:：-]+[^\\r\\n]+)?|番外[^\\r\\n]*)))\\s*$`, 'gim');
    }
  }

  private static addChapter(book: ParsedBook, title: string, content: string, index: number): void {
    const cleanTitle = title.trim().length === 0 ? `第 ${index} 章` : title.trim();
    const cleanContent = content.trim().length === 0 ? cleanTitle : content.trim();
    book.chapters.push(new ChapterRecord(cleanTitle, cleanContent));
  }

  private static stripExtension(name: string): string {
    const dot = name.lastIndexOf('.');
    if (dot > 0) {
      return name.substring(0, dot);
    }
    return name.trim().length === 0 ? '未命名 TXT' : name;
  }
}
