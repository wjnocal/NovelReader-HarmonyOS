import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ChapterRecord } from '../model/Models';
import { LibraryStore } from './LibraryStore';

class ZipEntryInfo {
  name: string = '';
  path: string = '';
  nameBytes: Uint8Array = new Uint8Array(0);
  size: number = 0;
  crc: number = 0;
  offset: number = 0;
}

export class OnlineBookExporter {
  static async write(directory: string, title: string, author: string, description: string,
    chapters: Array<ChapterRecord>, format: string): Promise<string> {
    const normalizedFormat = format.toLowerCase() === 'epub' ? 'epub' : 'txt';
    const fileName = `${OnlineBookExporter.safeName(title)}.${normalizedFormat}`;
    const output = `${directory}/${fileName}`;
    if (normalizedFormat === 'txt') {
      OnlineBookExporter.writeTxt(output, title, author, description, chapters);
    } else {
      await OnlineBookExporter.writeEpub(directory, output, title, author, description, chapters);
    }
    return output;
  }

  private static writeTxt(path: string, title: string, author: string, description: string,
    chapters: Array<ChapterRecord>): void {
    const parts = new Array<string>();
    parts.push(title);
    parts.push(`作者：${author}`);
    if (description.trim().length > 0) {
      parts.push(description.trim());
    }
    chapters.forEach((chapter: ChapterRecord): void => {
      parts.push(chapter.title);
      parts.push(chapter.content);
    });
    OnlineBookExporter.writeText(path, parts.join('\n\n'));
  }

  private static async writeEpub(directory: string, output: string, title: string, author: string,
    description: string, chapters: Array<ChapterRecord>): Promise<void> {
    const stage = `${directory}/epub_build`;
    LibraryStore.deleteRecursively(stage);
    LibraryStore.ensureDirectory(`${stage}/META-INF`);
    LibraryStore.ensureDirectory(`${stage}/OEBPS/Text`);
    try {
      OnlineBookExporter.writeText(`${stage}/mimetype`, 'application/epub+zip');
      OnlineBookExporter.writeText(`${stage}/META-INF/container.xml`,
        '<?xml version="1.0" encoding="UTF-8"?>' +
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">' +
        '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>' +
        '</rootfiles></container>');

      const manifest = new Array<string>();
      const spine = new Array<string>();
      const nav = new Array<string>();
      const archiveEntries = new Array<ZipEntryInfo>();
      chapters.forEach((chapter: ChapterRecord, index: number): void => {
        const id = `chapter${index + 1}`;
        const href = `Text/${id}.xhtml`;
        manifest.push(`<item id="${id}" href="${href}" media-type="application/xhtml+xml"/>`);
        spine.push(`<itemref idref="${id}"/>`);
        nav.push(`<li><a href="${href}">${OnlineBookExporter.xml(chapter.title)}</a></li>`);
        const paragraphs = chapter.content.split(/\n+/).filter((value: string): boolean => value.trim().length > 0)
          .map((value: string): string => `<p>${OnlineBookExporter.xml(value.trim())}</p>`).join('');
        OnlineBookExporter.writeText(`${stage}/OEBPS/${href}`,
          `<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml">` +
          `<head><title>${OnlineBookExporter.xml(chapter.title)}</title></head><body>` +
          `<h1>${OnlineBookExporter.xml(chapter.title)}</h1>${paragraphs}</body></html>`);
        archiveEntries.push(OnlineBookExporter.zipEntry(`${stage}/OEBPS/${href}`, `OEBPS/${href}`));
      });
      OnlineBookExporter.writeText(`${stage}/OEBPS/nav.xhtml`,
        `<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" ` +
        `xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body>` +
        `<nav epub:type="toc"><h1>目录</h1><ol>${nav.join('')}</ol></nav></body></html>`);
      OnlineBookExporter.writeText(`${stage}/OEBPS/content.opf`,
        `<?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" ` +
        `version="3.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">` +
        `<dc:identifier id="book-id">novelreader-${Date.now()}</dc:identifier>` +
        `<dc:title>${OnlineBookExporter.xml(title)}</dc:title>` +
        `<dc:creator>${OnlineBookExporter.xml(author)}</dc:creator>` +
        `<dc:description>${OnlineBookExporter.xml(description)}</dc:description>` +
        `<dc:language>zh-CN</dc:language><meta property="dcterms:modified">${OnlineBookExporter.epubDate()}</meta>` +
        `</metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" ` +
        `properties="nav"/>${manifest.join('')}</manifest><spine>${spine.join('')}</spine></package>`);
      archiveEntries.unshift(OnlineBookExporter.zipEntry(`${stage}/META-INF/container.xml`, 'META-INF/container.xml'));
      archiveEntries.unshift(OnlineBookExporter.zipEntry(`${stage}/mimetype`, 'mimetype'));
      archiveEntries.push(OnlineBookExporter.zipEntry(`${stage}/OEBPS/nav.xhtml`, 'OEBPS/nav.xhtml'));
      archiveEntries.push(OnlineBookExporter.zipEntry(`${stage}/OEBPS/content.opf`, 'OEBPS/content.opf'));
      OnlineBookExporter.writeStoredZip(output, archiveEntries);
    } finally {
      LibraryStore.deleteRecursively(stage);
    }
  }

  private static safeName(value: string): string {
    const cleaned = value.replace(/[\\/:*?"<>|]/g, '_').trim();
    return cleaned.length > 0 ? cleaned : `网络小说_${Date.now()}`;
  }

  private static writeText(path: string, content: string): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
  }

  private static zipEntry(path: string, name: string): ZipEntryInfo {
    const entry = new ZipEntryInfo();
    entry.path = path;
    entry.name = name;
    entry.nameBytes = new util.TextEncoder().encodeInto(name);
    const bytes = OnlineBookExporter.readBytes(path);
    entry.size = bytes.length;
    entry.crc = OnlineBookExporter.crc32(bytes);
    return entry;
  }

  private static writeStoredZip(path: string, entries: Array<ZipEntryInfo>): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    let offset = 0;
    try {
      entries.forEach((entry: ZipEntryInfo): void => {
        entry.offset = offset;
        const header = new Uint8Array(30);
        const view = new DataView(header.buffer);
        view.setUint32(0, 0x04034B50, true);
        view.setUint16(4, 20, true);
        view.setUint16(6, 0x0800, true);
        view.setUint16(8, 0, true);
        view.setUint32(14, entry.crc, true);
        view.setUint32(18, entry.size, true);
        view.setUint32(22, entry.size, true);
        view.setUint16(26, entry.nameBytes.length, true);
        fs.writeSync(file.fd, header);
        fs.writeSync(file.fd, entry.nameBytes);
        fs.writeSync(file.fd, OnlineBookExporter.readBytes(entry.path));
        offset += header.length + entry.nameBytes.length + entry.size;
      });
      const centralOffset = offset;
      entries.forEach((entry: ZipEntryInfo): void => {
        const header = new Uint8Array(46);
        const view = new DataView(header.buffer);
        view.setUint32(0, 0x02014B50, true);
        view.setUint16(4, 20, true);
        view.setUint16(6, 20, true);
        view.setUint16(8, 0x0800, true);
        view.setUint16(10, 0, true);
        view.setUint32(16, entry.crc, true);
        view.setUint32(20, entry.size, true);
        view.setUint32(24, entry.size, true);
        view.setUint16(28, entry.nameBytes.length, true);
        view.setUint32(42, entry.offset, true);
        fs.writeSync(file.fd, header);
        fs.writeSync(file.fd, entry.nameBytes);
        offset += header.length + entry.nameBytes.length;
      });
      const end = new Uint8Array(22);
      const endView = new DataView(end.buffer);
      endView.setUint32(0, 0x06054B50, true);
      endView.setUint16(8, entries.length, true);
      endView.setUint16(10, entries.length, true);
      endView.setUint32(12, offset - centralOffset, true);
      endView.setUint32(16, centralOffset, true);
      fs.writeSync(file.fd, end);
    } finally {
      fs.closeSync(file);
    }
  }

  private static readBytes(path: string): Uint8Array {
    const size = fs.statSync(path).size;
    const buffer = new ArrayBuffer(size);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    let length = 0;
    try {
      length = fs.readSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    return new Uint8Array(buffer, 0, length);
  }

  private static crc32(bytes: Uint8Array): number {
    let crc = 0xFFFFFFFF;
    for (let index = 0; index < bytes.length; index++) {
      crc ^= bytes[index];
      for (let bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) === 1 ? 0xEDB88320 : 0);
      }
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  private static xml(value: string): string {
    return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
  }

  private static epubDate(): string {
    return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  }
}
