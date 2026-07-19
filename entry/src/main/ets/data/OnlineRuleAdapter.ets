import { HtmlNode, SimpleHtml } from './SimpleHtml';

class Quanben5SearchResponse {
  content: string = '';
}

export class OnlineRuleAdapter {
  static selector(rule: string): string {
    let end = rule.length;
    const jsIndex = rule.indexOf('@js:');
    const javaIndex = rule.indexOf('@java:');
    if (jsIndex >= 0) {
      end = Math.min(end, jsIndex);
    }
    if (javaIndex >= 0) {
      end = Math.min(end, javaIndex);
    }
    return rule.substring(0, end).trim();
  }

  static buildSearchUrl(sourceId: string, rule: string, keyword: string): string {
    if (!rule.startsWith('@js:')) {
      return rule.replace('%s', encodeURIComponent(keyword));
    }
    if (sourceId !== 'quanben5') {
      throw new Error('暂不支持这个书源的动态搜索地址');
    }
    const alphabet = 'PXhw7UT1B0a9kQDKZsjIASmOezxYG4CHo5Jyfg2b8FLpEvRr3WtVnlqMidu6cN';
    const encoded = encodeURIComponent(keyword);
    let encrypted = '';
    for (let index = 0; index < encoded.length; index++) {
      const value = encoded.charAt(index);
      const alphabetIndex = alphabet.indexOf(value);
      const shifted = alphabetIndex < 0 ? value : alphabet.charAt((alphabetIndex + 3) % alphabet.length);
      encrypted += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
      encrypted += shifted;
      encrypted += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
    }
    return `https://quanben5.com/?c=book&a=search.json&callback=search&keywords=${encoded}&b=${encodeURIComponent(encrypted)}`;
  }

  static preprocessSearchHtml(sourceId: string, response: string): string {
    if (sourceId !== 'quanben5') {
      return response;
    }
    const match = /search\((\{[\s\S]*\})\)\s*;?/.exec(response);
    if (match === null) {
      return response;
    }
    try {
      const parsed = JSON.parse(match[1]) as Quanben5SearchResponse;
      return parsed.content.trim().length > 0 ? parsed.content : response;
    } catch (error) {
      return response;
    }
  }

  static chapterText(content: HtmlNode, rule: string): string {
    if (rule.indexOf('data-id') >= 0) {
      const blocks = SimpleHtml.select(content, 'dd[data-id]');
      if (blocks.length > 0) {
        blocks.sort((left: HtmlNode, right: HtmlNode): number => Number(left.attr('data-id')) - Number(right.attr('data-id')));
        return blocks.map((block: HtmlNode): string => block.text()).join('\n\n');
      }
    }
    const text = content.text();
    if (rule.indexOf('base64.decode') < 0 && text.indexOf('document.writeln') < 0) {
      return text;
    }
    const pattern = /document\.writeln\(qsbs\.bb\(['"]([^'"]+)['"]\)\);?/gi;
    let transformed = '';
    let start = 0;
    let match: RegExpExecArray | null = pattern.exec(text);
    while (match !== null) {
      transformed += text.substring(start, match.index);
      transformed += OnlineRuleAdapter.decodeBase64Utf8(match[1]);
      start = pattern.lastIndex;
      match = pattern.exec(text);
    }
    if (start === 0) {
      return text;
    }
    transformed += text.substring(start);
    return SimpleHtml.parse(transformed, content.baseUrl).text();
  }

  static applyTocTransform(document: HtmlNode, sourceId: string): void {
    if (sourceId !== 'wxsy') {
      return;
    }
    const htmlText = document.text();
    const hiddenFromStart = OnlineRuleAdapter.countMatches(htmlText,
      /\.section-list\.ycxsid\s*>\s*li:nth-child\(\d+\)\s*\{\s*display\s*:\s*none/gi);
    const hiddenFromEnd = OnlineRuleAdapter.countMatches(htmlText,
      /\.section-list\.ycxsid\s*>\s*li:nth-last-child\(\d+\)\s*\{\s*display\s*:\s*none/gi);
    SimpleHtml.select(document, 'ul.section-list.ycxsid').forEach((list: HtmlNode): void => {
      let items = list.children.filter((item: HtmlNode): boolean => item.tag === 'li');
      for (let index = 0; index < hiddenFromStart && items.length > 0; index++) {
        items[0].remove();
        items = list.children.filter((item: HtmlNode): boolean => item.tag === 'li');
      }
      for (let index = 0; index < hiddenFromEnd && items.length > 0; index++) {
        items[items.length - 1].remove();
        items = list.children.filter((item: HtmlNode): boolean => item.tag === 'li');
      }
    });
  }

  static decodeBase64Utf8(encoded: string): string {
    try {
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      const clean = encoded.replace(/\s+/g, '').replace(/-/g, '+').replace(/_/g, '/');
      const output = new Array<number>();
      for (let index = 0; index < clean.length; index += 4) {
        const first = alphabet.indexOf(clean.charAt(index));
        const second = alphabet.indexOf(clean.charAt(index + 1));
        const thirdCharacter = clean.charAt(index + 2);
        const fourthCharacter = clean.charAt(index + 3);
        const third = thirdCharacter === '=' || thirdCharacter.length === 0 ? 0 : alphabet.indexOf(thirdCharacter);
        const fourth = fourthCharacter === '=' || fourthCharacter.length === 0 ? 0 : alphabet.indexOf(fourthCharacter);
        if (first < 0 || second < 0 || third < 0 || fourth < 0) {
          return encoded;
        }
        output.push((first << 2) | (second >> 4));
        if (thirdCharacter !== '=' && thirdCharacter.length > 0) {
          output.push(((second & 15) << 4) | (third >> 2));
        }
        if (fourthCharacter !== '=' && fourthCharacter.length > 0) {
          output.push(((third & 3) << 6) | fourth);
        }
      }
      const bytes = new Uint8Array(output.length);
      for (let index = 0; index < output.length; index++) {
        bytes[index] = output[index];
      }
      return OnlineRuleAdapter.decodeUtf8(bytes);
    } catch (error) {
      return encoded;
    }
  }

  private static decodeUtf8(bytes: Uint8Array): string {
    let output = '';
    for (let index = 0; index < bytes.length;) {
      const first = bytes[index++];
      if (first < 0x80) {
        output += String.fromCharCode(first);
        continue;
      }
      if ((first & 0xE0) === 0xC0 && index < bytes.length) {
        const codePoint = ((first & 0x1F) << 6) | (bytes[index++] & 0x3F);
        output += String.fromCharCode(codePoint);
        continue;
      }
      if ((first & 0xF0) === 0xE0 && index + 1 < bytes.length) {
        const codePoint = ((first & 0x0F) << 12) | ((bytes[index++] & 0x3F) << 6) | (bytes[index++] & 0x3F);
        output += String.fromCharCode(codePoint);
        continue;
      }
      if ((first & 0xF8) === 0xF0 && index + 2 < bytes.length) {
        const codePoint = ((first & 0x07) << 18) | ((bytes[index++] & 0x3F) << 12) |
          ((bytes[index++] & 0x3F) << 6) | (bytes[index++] & 0x3F);
        const adjusted = codePoint - 0x10000;
        output += String.fromCharCode(0xD800 + (adjusted >> 10), 0xDC00 + (adjusted & 0x3FF));
        continue;
      }
      output += '\uFFFD';
    }
    return output;
  }

  private static countMatches(value: string, pattern: RegExp): number {
    const matches = value.match(pattern);
    return matches === null ? 0 : matches.length;
  }
}
