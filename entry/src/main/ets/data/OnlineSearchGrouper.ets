import { OnlineBookGroup, OnlineBookResult } from '../model/Models';

export class OnlineSearchGrouper {
  static group(results: Array<OnlineBookResult>, keyword: string): Array<OnlineBookGroup> {
    const groups = new Map<string, OnlineBookGroup>();
    results.forEach((result: OnlineBookResult): void => {
      const key = OnlineSearchGrouper.normalize(result.bookName);
      if (key.length === 0) {
        return;
      }
      let group = groups.get(key);
      if (group === undefined) {
        group = new OnlineBookGroup();
        group.title = result.bookName.trim();
        group.author = result.author.trim();
        groups.set(key, group);
      }
      if (!group.versions.some((item: OnlineBookResult): boolean =>
        item.sourceId === result.sourceId && item.url === result.url)) {
        group.versions.push(result);
      }
      if (group.author.length === 0 && result.author.trim().length > 0) {
        group.author = result.author.trim();
      }
    });

    const output = Array.from(groups.values());
    output.forEach((group: OnlineBookGroup): void => {
      group.versions.sort((left: OnlineBookResult, right: OnlineBookResult): number => {
        const scoreDifference = OnlineSearchGrouper.score(right, keyword) -
          OnlineSearchGrouper.score(left, keyword);
        return scoreDifference !== 0 ? scoreDifference : left.sourceName.localeCompare(right.sourceName);
      });
      group.score = OnlineSearchGrouper.score(group.versions[0], keyword) + Math.min(50, group.versions.length * 5);
    });
    output.sort((left: OnlineBookGroup, right: OnlineBookGroup): number => {
      const scoreDifference = right.score - left.score;
      return scoreDifference !== 0 ? scoreDifference : left.title.localeCompare(right.title);
    });
    return output;
  }

  static score(result: OnlineBookResult, keyword: string): number {
    const title = OnlineSearchGrouper.normalize(result.bookName);
    const author = OnlineSearchGrouper.normalize(result.author);
    const latest = OnlineSearchGrouper.normalize(result.latestChapter);
    const query = OnlineSearchGrouper.normalize(keyword);
    if (query.length === 0) {
      return 0;
    }
    let score = 0;
    if (title === query) {
      score += 10000;
    } else if (title.startsWith(query)) {
      score += 8000;
    } else if (title.indexOf(query) >= 0) {
      score += 6500;
    } else if (query.indexOf(title) >= 0) {
      score += 5000;
    }
    if (title.indexOf(query) >= 0) {
      score += 1200;
    }
    if (author.indexOf(query) >= 0) {
      score += 700;
    }
    if (latest.indexOf(query) >= 0) {
      score += 200;
    }
    keyword.trim().split(/\s+/).forEach((token: string): void => {
      const normalizedToken = OnlineSearchGrouper.normalize(token);
      if (normalizedToken.length > 0 && title.indexOf(normalizedToken) >= 0) {
        score += 150;
      }
    });
    return score;
  }

  private static normalize(value: string): string {
    return value.replace(/[\s\u3000·•:：,，。.!！?？《》〈〉「」『』()（）\[\]]/g, '').toLowerCase();
  }
}
