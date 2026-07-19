import { fileIo as fs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { ChapterRecord, ParsedBook } from '../model/Models';
import { LibraryStore } from '../data/LibraryStore';

class ManifestItem {
  id: string = '';
  href: string = '';
  mediaType: string = '';
  properties: string = '';
}

export class EpubParser {
  static async parse(epubPath: string, extractDir: string, fallbackTitle: string): Promise<ParsedBook> {
    LibraryStore.deleteRecursively(extractDir);
    LibraryStore.ensureDirectory(extractDir);
    await zlib.decompressFile(epubPath, extractDir);

    try {
      const container = fs.readTextSync(`${extractDir}/META-INF/container.xml`);
      const rootFile = EpubParser.firstAttribute(container, 'rootfile', 'full-path');
      if (rootFile.length === 0) {
        throw new Error('EPUB 缺少 OPF 路径');
      }

      const opfPath = EpubParser.normalizePath(rootFile);
      const opf = fs.readTextSync(`${extractDir}/${opfPath}`);
      const basePath = EpubParser.parentPath(opfPath);
      const manifest = EpubParser.readManifest(opf);
      const tocTitles = EpubParser.readTocTitles(extractDir, basePath, manifest);

      const parsed = new ParsedBook();
      parsed.title = EpubParser.firstTagText(opf, 'dc:title', EpubParser.stripExtension(fallbackTitle));
      parsed.author = EpubParser.firstTagText(opf, 'dc:creator', '本地 EPUB');
      parsed.description = EpubParser.firstTagText(opf, 'dc:description', '');
      parsed.fileType = 'epub';

      const spinePattern = /<itemref\b[^>]*>/gi;
      let spineMatch: RegExpExecArray | null = spinePattern.exec(opf);
      let chapterNumber = 1;
      while (spineMatch !== null) {
        const idRef = EpubParser.attribute(spineMatch[0], 'idref');
        const item = EpubParser.findManifestItem(manifest, idRef);
        if (item !== undefined && item.href.length > 0) {
          const relativePath = EpubParser.normalizeHref(`${basePath}${item.href}`);
          try {
            const html = fs.readTextSync(`${extractDir}/${relativePath}`);
            let title = tocTitles.get(EpubParser.normalizeHref(item.href));
            if (title === undefined || title.length === 0) {
              title = EpubParser.firstHeading(html, `第 ${chapterNumber} 章`);
            }
            const content = EpubParser.removeLeadingTitle(EpubParser.htmlToText(html), title);
            if (content.length > 0) {
              parsed.chapters.push(new ChapterRecord(title, content));
              chapterNumber++;
            }
          } catch (error) {
            // Ignore missing optional spine items and keep importing readable chapters.
          }
        }
        spineMatch = spinePattern.exec(opf);
      }

      if (parsed.chapters.length === 0) {
        throw new Error('EPUB 没有可读取的章节');
      }
      return parsed;
    } finally {
      LibraryStore.deleteRecursively(extractDir);
    }
  }

  private static readManifest(opf: string): Array<ManifestItem> {
    const items = new Array<ManifestItem>();
    const pattern = /<item\b[^>]*>/gi;
    let match: RegExpExecArray | null = pattern.exec(opf);
    while (match !== null) {
      const item = new ManifestItem();
      item.id = EpubParser.attribute(match[0], 'id');
      item.href = EpubParser.attribute(match[0], 'href');
      item.mediaType = EpubParser.attribute(match[0], 'media-type');
      item.properties = EpubParser.attribute(match[0], 'properties');
      if (item.id.length > 0) {
        items.push(item);
      }
      match = pattern.exec(opf);
    }
    return items;
  }

  private static readTocTitles(extractDir: string, basePath: string,
    manifest: Array<ManifestItem>): Map<string, string> {
    const titles = new Map<string, string>();
    manifest.forEach((item: ManifestItem) => {
      if (item.properties.indexOf('nav') < 0 && item.mediaType !== 'application/x-dtbncx+xml') {
        return;
      }
      try {
        const toc = fs.readTextSync(`${extractDir}/${EpubParser.normalizePath(`${basePath}${item.href}`)}`);
        const tocBase = EpubParser.parentPath(item.href);
        EpubParser.navigationTitles(toc).forEach((title: string, href: string): void => {
          titles.set(EpubParser.normalizeHref(`${tocBase}${href}`), title);
        });
      } catch (error) {
        // A broken TOC should not prevent reading spine content.
      }
    });
    return titles;
  }

  static navigationTitles(toc: string): Map<string, string> {
    const titles = new Map<string, string>();
    const navPattern = /<a\b[^>]*href\s*=\s*(["'])(.*?)\1[^>]*>([\s\S]*?)<\/a>/gi;
    let navMatch: RegExpExecArray | null = navPattern.exec(toc);
    while (navMatch !== null) {
      const title = EpubParser.htmlToText(navMatch[3]);
      if (title.length > 0) {
        titles.set(navMatch[2], title);
      }
      navMatch = navPattern.exec(toc);
    }

    // EPUB 2 NCX stores the label before a self-closing content node.
    const ncxPattern = /<navLabel\b[^>]*>[\s\S]*?<text\b[^>]*>([\s\S]*?)<\/text>[\s\S]*?<\/navLabel>[\s\S]*?<content\b[^>]*src\s*=\s*(["'])(.*?)\2[^>]*\/?\s*>/gi;
    let ncxMatch: RegExpExecArray | null = ncxPattern.exec(toc);
    while (ncxMatch !== null) {
      const title = EpubParser.htmlToText(ncxMatch[1]);
      if (title.length > 0) {
        titles.set(ncxMatch[3], title);
      }
      ncxMatch = ncxPattern.exec(toc);
    }
    return titles;
  }

  private static findManifestItem(items: Array<ManifestItem>, id: string): ManifestItem | undefined {
    return items.find((item: ManifestItem) => item.id === id);
  }

  private static firstAttribute(xml: string, tag: string, name: string): string {
    const pattern = new RegExp(`<${tag}\\b[^>]*>`, 'i');
    const match = pattern.exec(xml);
    return match === null ? '' : EpubParser.attribute(match[0], name);
  }

  private static attribute(tag: string, name: string): string {
    const pattern = new RegExp(`${name}\\s*=\\s*(["'])(.*?)\\1`, 'i');
    const match = pattern.exec(tag);
    return match === null ? '' : EpubParser.decodeEntities(match[2]);
  }

  private static firstTagText(xml: string, tag: string, fallback: string): string {
    const pattern = new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i');
    const match = pattern.exec(xml);
    if (match === null) {
      return fallback;
    }
    const value = EpubParser.htmlToText(match[1]);
    return value.length === 0 ? fallback : value;
  }

  private static firstHeading(html: string, fallback: string): string {
    const match = /<h[1-3]\b[^>]*>([\s\S]*?)<\/h[1-3]>/i.exec(html);
    if (match === null) {
      return fallback;
    }
    const value = EpubParser.htmlToText(match[1]);
    return value.length === 0 ? fallback : value;
  }

  private static htmlToText(html: string): string {
    const bodyMatch = /<body\b[^>]*>([\s\S]*?)<\/body>/i.exec(html);
    const content = bodyMatch === null ? html : bodyMatch[1];
    return EpubParser.decodeEntities(content
      .replace(/<script\b[\s\S]*?<\/script>/gi, '')
      .replace(/<style\b[\s\S]*?<\/style>/gi, '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/(p|div|section|article|h[1-6]|li)>/gi, '\n\n')
      .replace(/<[^>]+>/g, ''))
      .replace(/[\t\f\v ]+/g, ' ')
      .replace(/ *\n */g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  private static removeLeadingTitle(content: string, title: string): string {
    if (title.length === 0 || !content.startsWith(title) || content.length <= title.length) {
      return content;
    }
    const remaining = content.substring(title.length);
    return remaining.startsWith('\n') ? remaining.trim() : content;
  }

  private static decodeEntities(text: string): string {
    return text.replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"')
      .replace(/&#39;|&apos;/gi, "'")
      .replace(/&#x([0-9a-f]+);/gi, (whole: string, digits: string) =>
        EpubParser.characterForCodePoint(parseInt(digits, 16)))
      .replace(/&#(\d+);/g, (whole: string, digits: string) =>
        EpubParser.characterForCodePoint(Number(digits)));
  }

  private static characterForCodePoint(value: number): string {
    if (value <= 0xFFFF) {
      return String.fromCharCode(value);
    }
    const adjusted = value - 0x10000;
    return String.fromCharCode(0xD800 + (adjusted >> 10), 0xDC00 + (adjusted & 0x3FF));
  }

  private static normalizeHref(href: string): string {
    const hash = href.indexOf('#');
    const value = hash >= 0 ? href.substring(0, hash) : href;
    try {
      return EpubParser.normalizePath(decodeURIComponent(value));
    } catch (error) {
      return EpubParser.normalizePath(value);
    }
  }

  private static normalizePath(path: string): string {
    const segments = path.replace(/\\/g, '/').split('/');
    const output = new Array<string>();
    segments.forEach((segment: string) => {
      if (segment.length === 0 || segment === '.') {
        return;
      }
      if (segment === '..') {
        if (output.length > 0) {
          output.pop();
        }
      } else {
        output.push(segment);
      }
    });
    return output.join('/');
  }

  private static parentPath(path: string): string {
    const slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash + 1);
  }

  private static stripExtension(name: string): string {
    const dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
