export class HtmlNode {
  tag: string = '';
  attributes: Map<string, string> = new Map<string, string>();
  children: Array<HtmlNode> = new Array<HtmlNode>();
  parent: HtmlNode | undefined = undefined;
  textValue: string = '';
  baseUrl: string = '';

  constructor(tag: string = '', parent?: HtmlNode) {
    this.tag = tag.toLowerCase();
    this.parent = parent;
  }

  attr(name: string): string {
    return this.attributes.get(name.toLowerCase()) ?? '';
  }

  text(): string {
    if (this.tag === 'br' || this.tag === 'hr') {
      return '\n';
    }
    let output = this.textValue;
    this.children.forEach((child: HtmlNode): void => {
      const childText = child.text();
      if (childText.length > 0) {
        const block = child.tag === 'p' || child.tag === 'div' || child.tag === 'li' || child.tag === 'dd';
        output += `${output.length > 0 ? (block ? '\n' : ' ') : ''}${childText}${block ? '\n' : ''}`;
      }
    });
    return SimpleHtml.cleanText(output);
  }

  absoluteUrl(attribute: string): string {
    return SimpleHtml.resolveUrl(this.baseUrl, this.attr(attribute));
  }

  remove(): void {
    if (this.parent === undefined) {
      return;
    }
    const index = this.parent.children.indexOf(this);
    if (index >= 0) {
      this.parent.children.splice(index, 1);
    }
  }
}

class SelectorStep {
  selector: string = '';
  combinator: string = ' ';
}

export class SimpleHtml {
  static parse(html: string, baseUrl: string): HtmlNode {
    const root = new HtmlNode('document');
    root.baseUrl = baseUrl;
    const stack = new Array<HtmlNode>();
    stack.push(root);
    const tokenPattern = /<(script|style|textarea)\b[^>]*>[\s\S]*?<\/\1\s*>|<!--[\s\S]*?-->|<![^>]*>|<[^>]+>|[^<]+/gi;
    const tokens = html.match(tokenPattern) ?? new Array<string>();
    const voidTags = new Set<string>(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr']);
    tokens.forEach((token: string): void => {
      const rawText = token.match(/^<(script|style|textarea)\b([^>]*)>([\s\S]*?)<\/\1\s*>$/i);
      if (rawText !== null) {
        const parent = stack[stack.length - 1];
        const node = new HtmlNode(rawText[1], parent);
        node.baseUrl = baseUrl;
        SimpleHtml.parseAttributes(rawText[2], node.attributes);
        node.textValue = rawText[3];
        parent.children.push(node);
        return;
      }
      if (token.startsWith('<!--') || token.startsWith('<!')) {
        return;
      }
      if (token.startsWith('</')) {
        const name = token.substring(2, token.length - 1).trim().toLowerCase();
        while (stack.length > 1) {
          const popped = stack.pop();
          if (popped !== undefined && popped.tag === name) {
            break;
          }
        }
        return;
      }
      if (token.startsWith('<')) {
        const selfClosing = token.endsWith('/>');
        const body = token.substring(1, token.length - (selfClosing ? 2 : 1)).trim();
        const nameMatch = body.match(/^([^\s/>]+)/);
        if (nameMatch === null) {
          return;
        }
        SimpleHtml.closeOptionalElement(stack, nameMatch[1].toLowerCase());
        const parent = stack[stack.length - 1];
        const node = new HtmlNode(nameMatch[1], parent);
        node.baseUrl = baseUrl;
        SimpleHtml.parseAttributes(body.substring(nameMatch[0].length), node.attributes);
        parent.children.push(node);
        if (!selfClosing && !voidTags.has(node.tag)) {
          stack.push(node);
        }
        return;
      }
      const clean = SimpleHtml.decodeEntities(token);
      if (clean.trim().length > 0) {
        const parent = stack[stack.length - 1];
        parent.textValue += `${parent.textValue.length > 0 ? ' ' : ''}${clean}`;
      }
    });
    return root;
  }

  static select(scope: HtmlNode, rule: string): Array<HtmlNode> {
    const output = new Array<HtmlNode>();
    SimpleHtml.splitOutside(rule, ',').forEach((group: string): void => {
      const steps = SimpleHtml.selectorSteps(group.trim());
      if (steps.length === 0) {
        return;
      }
      let current = new Array<HtmlNode>();
      current.push(scope);
      steps.forEach((step: SelectorStep, index: number): void => {
        const candidates = new Array<HtmlNode>();
        current.forEach((node: HtmlNode): void => {
          if (index === 0 || step.combinator === ' ') {
            SimpleHtml.descendants(node, candidates);
          } else if (step.combinator === '>') {
            node.children.forEach((child: HtmlNode): void => {
              candidates.push(child);
            });
          } else if (step.combinator === '~') {
            SimpleHtml.followingSiblings(node).forEach((sibling: HtmlNode): void => {
              candidates.push(sibling);
            });
          }
        });
        current = SimpleHtml.unique(candidates.filter((node: HtmlNode): boolean => SimpleHtml.matches(node, step.selector)));
      });
      current.forEach((node: HtmlNode): void => {
        if (output.indexOf(node) < 0) {
          output.push(node);
        }
      });
    });
    return output;
  }

  static cleanText(value: string): string {
    return SimpleHtml.decodeEntities(value).replace(/[\t\f\v ]+/g, ' ').replace(/\s*\n\s*/g, '\n').trim();
  }

  static resolveUrl(baseUrl: string, value: string): string {
    const target = SimpleHtml.decodeEntities(value).trim();
    if (target.length === 0) {
      return '';
    }
    if (/^[a-z][a-z0-9+.-]*:/i.test(target)) {
      return target;
    }
    const originMatch = baseUrl.match(/^(https?:\/\/[^/]+)/i);
    const origin = originMatch === null ? '' : originMatch[1];
    if (target.startsWith('//')) {
      return `${baseUrl.startsWith('https:') ? 'https:' : 'http:'}${target}`;
    }
    if (target.startsWith('/')) {
      return `${origin}${target}`;
    }
    const cleanBase = baseUrl.split('#')[0].split('?')[0];
    const baseDirectory = cleanBase.endsWith('/') ? cleanBase : cleanBase.substring(0, cleanBase.lastIndexOf('/') + 1);
    const parts = `${baseDirectory}${target}`.split('/');
    const normalized = new Array<string>();
    parts.forEach((part: string): void => {
      if (part === '..' && normalized.length > 3) {
        normalized.pop();
      } else if (part !== '.') {
        normalized.push(part);
      }
    });
    return normalized.join('/');
  }

  private static parseAttributes(source: string, output: Map<string, string>): void {
    const pattern = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
    let match: RegExpExecArray | null = pattern.exec(source);
    while (match !== null) {
      const value = match[2] ?? match[3] ?? match[4] ?? '';
      output.set(match[1].toLowerCase(), SimpleHtml.decodeEntities(value));
      match = pattern.exec(source);
    }
  }

  private static selectorSteps(group: string): Array<SelectorStep> {
    const steps = new Array<SelectorStep>();
    let buffer = '';
    let depth = 0;
    let pending = ' ';
    const flush = (): void => {
      const value = buffer.trim();
      if (value.length > 0) {
        const step = new SelectorStep();
        step.selector = value;
        step.combinator = steps.length === 0 ? ' ' : pending;
        steps.push(step);
      }
      buffer = '';
    };
    for (let index = 0; index < group.length; index++) {
      const character = group[index];
      if (character === '[' || character === '(') {
        depth++;
      } else if (character === ']' || character === ')') {
        depth--;
      }
      if (depth === 0 && (character === '>' || character === '~')) {
        flush();
        pending = character;
        continue;
      }
      if (depth === 0 && /\s/.test(character)) {
        if (buffer.trim().length > 0) {
          flush();
          pending = ' ';
        }
        continue;
      }
      buffer += character;
    }
    flush();
    return steps;
  }

  private static matches(node: HtmlNode, selector: string): boolean {
    const notRules = new Array<string>();
    let simple = selector.replace(/:not\(([^)]+)\)/g, (_full: string, inner: string): string => {
      notRules.push(inner);
      return '';
    });
    for (let index = 0; index < notRules.length; index++) {
      if (SimpleHtml.matches(node, notRules[index])) {
        return false;
      }
    }
    const nthMatch = simple.match(/:nth-(child|of-type)\(([^)]+)\)/);
    if (nthMatch !== null) {
      if (!SimpleHtml.matchesNth(node, nthMatch[1] === 'of-type', nthMatch[2])) {
        return false;
      }
      simple = simple.replace(nthMatch[0], '');
    }
    const attributePattern = /\[([^\]=]+)(?:=["']?([^\]"']*)["']?)?\]/g;
    let attributeMatch: RegExpExecArray | null = attributePattern.exec(simple);
    while (attributeMatch !== null) {
      const actual = node.attr(attributeMatch[1]);
      if (actual.length === 0 || (attributeMatch[2] !== undefined && actual !== attributeMatch[2])) {
        return false;
      }
      attributeMatch = attributePattern.exec(simple);
    }
    simple = simple.replace(attributePattern, '');
    const idMatch = simple.match(/#([\w-]+)/);
    if (idMatch !== null && node.attr('id') !== idMatch[1]) {
      return false;
    }
    const classMatches = simple.match(/\.([\w-]+)/g) ?? new Array<string>();
    const classes = node.attr('class').split(/\s+/);
    for (let index = 0; index < classMatches.length; index++) {
      if (classes.indexOf(classMatches[index].substring(1)) < 0) {
        return false;
      }
    }
    const tagMatch = simple.match(/^[a-zA-Z][\w-]*/);
    return tagMatch === null || node.tag === tagMatch[0].toLowerCase();
  }

  private static matchesNth(node: HtmlNode, ofType: boolean, expression: string): boolean {
    if (node.parent === undefined) {
      return false;
    }
    const siblings = ofType ? node.parent.children.filter((item: HtmlNode): boolean => item.tag === node.tag) : node.parent.children;
    const position = siblings.indexOf(node) + 1;
    const value = expression.replace(/\s+/g, '').toLowerCase();
    if (value === 'odd') {
      return position % 2 === 1;
    }
    if (value === 'even') {
      return position % 2 === 0;
    }
    if (/^\d+$/.test(value)) {
      return position === Number(value);
    }
    const formula = value.match(/^(-?\d*)n(?:\+(-?\d+))?$/);
    if (formula === null) {
      return false;
    }
    const coefficient = formula[1] === '' ? 1 : formula[1] === '-' ? -1 : Number(formula[1]);
    const offset = formula[2] === undefined ? 0 : Number(formula[2]);
    return coefficient === 0 ? position === offset : (position - offset) / coefficient >= 0 && (position - offset) % coefficient === 0;
  }

  private static closeOptionalElement(stack: Array<HtmlNode>, incoming: string): void {
    let inspect = true;
    while (inspect && stack.length > 1) {
      const current = stack[stack.length - 1].tag;
      const closesSame = (incoming === 'li' && current === 'li') ||
        ((incoming === 'dt' || incoming === 'dd') && (current === 'dt' || current === 'dd')) ||
        (incoming === 'tr' && current === 'tr') ||
        ((incoming === 'td' || incoming === 'th') && (current === 'td' || current === 'th')) ||
        (incoming === 'option' && current === 'option') || (incoming === 'p' && current === 'p');
      const closesParagraph = current === 'p' && (incoming === 'address' || incoming === 'article' ||
        incoming === 'aside' || incoming === 'blockquote' || incoming === 'div' || incoming === 'dl' ||
        incoming === 'fieldset' || incoming === 'footer' || incoming === 'form' || incoming === 'h1' ||
        incoming === 'h2' || incoming === 'h3' || incoming === 'h4' || incoming === 'h5' ||
        incoming === 'h6' || incoming === 'header' || incoming === 'hr' || incoming === 'menu' ||
        incoming === 'nav' || incoming === 'ol' || incoming === 'p' || incoming === 'pre' ||
        incoming === 'section' || incoming === 'table' || incoming === 'ul');
      if (closesSame || closesParagraph) {
        stack.pop();
      } else {
        inspect = false;
      }
    }
  }

  private static descendants(node: HtmlNode, output: Array<HtmlNode>): void {
    node.children.forEach((child: HtmlNode): void => {
      output.push(child);
      SimpleHtml.descendants(child, output);
    });
  }

  private static followingSiblings(node: HtmlNode): Array<HtmlNode> {
    if (node.parent === undefined) {
      return new Array<HtmlNode>();
    }
    const index = node.parent.children.indexOf(node);
    return node.parent.children.slice(index + 1);
  }

  private static unique(values: Array<HtmlNode>): Array<HtmlNode> {
    const output = new Array<HtmlNode>();
    values.forEach((value: HtmlNode): void => {
      if (output.indexOf(value) < 0) {
        output.push(value);
      }
    });
    return output;
  }

  private static splitOutside(source: string, delimiter: string): Array<string> {
    const output = new Array<string>();
    let start = 0;
    let depth = 0;
    for (let index = 0; index < source.length; index++) {
      const character = source[index];
      if (character === '[' || character === '(') {
        depth++;
      } else if (character === ']' || character === ')') {
        depth--;
      } else if (character === delimiter && depth === 0) {
        output.push(source.substring(start, index));
        start = index + 1;
      }
    }
    output.push(source.substring(start));
    return output;
  }

  private static decodeEntities(value: string): string {
    const named = new Map<string, string>([
      ['nbsp', ' '], ['amp', '&'], ['lt', '<'], ['gt', '>'], ['quot', '"'], ['apos', "'"], ['ldquo', '“'], ['rdquo', '”']
    ]);
    return value.replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, (_full: string, entity: string): string => {
      if (entity.startsWith('#x') || entity.startsWith('#X')) {
        return String.fromCharCode(parseInt(entity.substring(2), 16));
      }
      if (entity.startsWith('#')) {
        return String.fromCharCode(parseInt(entity.substring(1), 10));
      }
      return named.get(entity.toLowerCase()) ?? _full;
    });
  }
}
