import { describe, it, expect } from '@ohos/hypium';
import { EpubParser } from '../main/ets/parser/EpubParser';
import { ChapterSplitMode, TxtParser } from '../main/ets/parser/TxtParser';
import { LibraryStore } from '../main/ets/data/LibraryStore';
import { OnlineRuleAdapter } from '../main/ets/data/OnlineRuleAdapter';
import { OnlineSearchGrouper } from '../main/ets/data/OnlineSearchGrouper';
import { OnlinePageExtractor } from '../main/ets/data/OnlinePageExtractor';
import { SimpleHtml } from '../main/ets/data/SimpleHtml';
import { LibrarySnapshot, OnlineBookResult, OnlineExtractionRule } from '../main/ets/model/Models';

export default function localUnitTest() {
  describe('bookParser', () => {
    it('splitsCommonHeadingsInAutomaticMode', 0, () => {
      const parsed = TxtParser.parse('序章\n开场\n第1章 初见\n正文一\nChapter 2 Again\n正文二', 'sample.txt');
      expect(parsed.title).assertEqual('sample');
      expect(parsed.chapters.length).assertEqual(3);
      expect(parsed.chapters[0].title).assertEqual('序章');
      expect(parsed.chapters[1].title).assertEqual('第1章 初见');
      expect(parsed.chapters[2].title).assertEqual('Chapter 2 Again');
    });

    it('keepsPrefaceBeforeFirstChapter', 0, () => {
      const parsed = TxtParser.parse('这是前言\n第一章 开始\n第一段', 'preface.txt', ChapterSplitMode.CHINESE_CHAPTER);
      expect(parsed.chapters.length).assertEqual(2);
      expect(parsed.chapters[0].title).assertEqual('序章');
      expect(parsed.chapters[0].content).assertEqual('这是前言');
    });

    it('readsEpub2AndEpub3Navigation', 0, () => {
      const navigation = '<nav><a href="Text/one.xhtml">第一章</a></nav>' +
        '<navPoint><navLabel><text>第二章</text></navLabel><content src="Text/two.xhtml"/></navPoint>';
      const titles = EpubParser.navigationTitles(navigation);
      expect(titles.get('Text/one.xhtml')).assertEqual('第一章');
      expect(titles.get('Text/two.xhtml')).assertEqual('第二章');
    });

    it('migratesOldSettingsWithoutLosingPagedMode', 0, () => {
      const snapshot = JSON.parse('{"settings":{"readMode":0},"books":[],"notes":[]}') as LibrarySnapshot;
      const migrated = LibraryStore.normalizeSnapshot(snapshot);
      expect(migrated.settings.readMode).assertEqual(0);
      expect(migrated.settings.textSize).assertEqual(19);
      expect(migrated.bookmarks.length).assertEqual(0);
      expect(migrated.userName).assertEqual('默认用户');
    });

    it('parsesOnlineSourceSelectorsAndSupplementaryEntities', 0, () => {
      const document = SimpleHtml.parse('<dl><dt>最新</dt><dt>正文</dt><dd><a href="1.html">A&#x1F600;</a></dd>' +
        '<dd><a href="2.html">B</a></dd></dl>', 'https://example.com/book/');
      const chapters = SimpleHtml.select(document, 'dl > dt:nth-of-type(2) ~ dd > a');
      expect(chapters.length).assertEqual(2);
      expect(chapters[0].text()).assertEqual('A😀');
      expect(chapters[1].absoluteUrl('href')).assertEqual('https://example.com/book/2.html');
    });

    it('resolvesOptionValuePaginationLinks', 0, () => {
      const document = SimpleHtml.parse('<select><option value="../page-2.html">第二页</option></select>',
        'https://example.com/book/index.html');
      const options = SimpleHtml.select(document, 'select > option');
      expect(options.length).assertEqual(1);
      expect(options[0].absoluteUrl('value')).assertEqual('https://example.com/page-2.html');
    });

    it('decodesBase64AndRestoresDataIdChapterRules', 0, () => {
      expect(OnlineRuleAdapter.decodeBase64Utf8('PHA+5L2g5aW9PC9wPg==')).assertEqual('<p>你好</p>');
      const encoded = SimpleHtml.parse("<div id='content'><script>document.writeln(qsbs.bb('PHA+5L2g5aW9PC9wPg=='));</script></div>",
        'https://example.com/chapter.html');
      const encodedContent = SimpleHtml.select(encoded, '#content')[0];
      expect(encodedContent.text().indexOf('document.writeln') >= 0).assertTrue();
      expect(OnlineRuleAdapter.chapterText(encodedContent, '#content@java:base64.decode()')).assertEqual('你好');

      const shuffled = SimpleHtml.parse("<div id='txt'><dd data-id='2'>第二段</dd><dd data-id='1'>第一段</dd></div>",
        'https://example.com/chapter.html');
      const shuffledContent = SimpleHtml.select(shuffled, '#txt')[0];
      expect(OnlineRuleAdapter.chapterText(shuffledContent, '#txt@js:data-id')).assertEqual('第一段\n\n第二段');
    });

    it('adaptsDynamicSearchAndJsonpRules', 0, () => {
      const url = OnlineRuleAdapter.buildSearchUrl('quanben5', '@js:quanben5-search', '测试');
      expect(url.indexOf('https://quanben5.com/?c=book&a=search.json') === 0).assertTrue();
      expect(url.indexOf(`keywords=${encodeURIComponent('测试')}`) > 0).assertTrue();
      const html = OnlineRuleAdapter.preprocessSearchHtml('quanben5',
        'search({"content":"<div class=\\"pic_txt_list\\"><h3>结果</h3></div>"});');
      expect(html.indexOf('pic_txt_list') > 0).assertTrue();
    });

    it('removesHiddenWxsyTocEntries', 0, () => {
      const document = SimpleHtml.parse('<style>.section-list.ycxsid > li:nth-child(1){display:none}' +
        '.section-list.ycxsid > li:nth-last-child(1){display:none}</style>' +
        '<ul class="section-list ycxsid"><li>伪首章</li><li>正文</li><li>伪尾章</li></ul>', 'https://example.com/');
      OnlineRuleAdapter.applyTocTransform(document, 'wxsy');
      const items = SimpleHtml.select(document, 'ul.section-list.ycxsid > li');
      expect(items.length).assertEqual(1);
      expect(items[0].text()).assertEqual('正文');
    });

    it('mergesSameTitleAcrossSourcesAndRanksExactMatchFirst', 0, () => {
      const exactA = new OnlineBookResult();
      exactA.bookName = '剑来';
      exactA.author = '烽火戏诸侯';
      exactA.sourceId = 'source-a';
      exactA.sourceName = '书源 A';
      exactA.url = 'https://a.example/book/1';
      const exactB = new OnlineBookResult();
      exactB.bookName = '剑 来';
      exactB.author = '烽火戏诸侯';
      exactB.sourceId = 'source-b';
      exactB.sourceName = '书源 B';
      exactB.url = 'https://b.example/book/1';
      const partial = new OnlineBookResult();
      partial.bookName = '剑来外传';
      partial.sourceId = 'source-c';
      partial.sourceName = '书源 C';
      partial.url = 'https://c.example/book/1';
      const groups = OnlineSearchGrouper.group([partial, exactA, exactB], '剑来');
      expect(groups.length).assertEqual(2);
      expect(groups[0].title).assertEqual('剑来');
      expect(groups[0].versions.length).assertEqual(2);
      expect(groups[1].versions.length).assertEqual(1);
    });

    it('buildsAndParsesOnlineReaderExtractionPayload', 0, () => {
      const rule = new OnlineExtractionRule();
      rule.titleSelector = '.chapter-title';
      rule.contentSelector = '#chapter-content';
      rule.filterPattern = '广告';
      const script = OnlinePageExtractor.buildScript(rule);
      expect(script.indexOf('.chapter-title') >= 0).assertTrue();
      expect(script.indexOf('#chapter-content') >= 0).assertTrue();
      expect(script.indexOf('previousUrl') >= 0).assertTrue();
      expect(script.indexOf('previousChapterUrl') >= 0).assertTrue();
      expect(script.indexOf('nextPageUrl') >= 0).assertTrue();
      const payload = '{"url":"https://example.com/2","bookTitle":"示例","title":"第二章",' +
        '"content":"正文内容足够长","previousUrl":"https://example.com/1",' +
        '"nextUrl":"https://example.com/3","previousChapterUrl":"https://example.com/1",' +
        '"nextChapterUrl":"https://example.com/3","previousPageUrl":"",' +
        '"nextPageUrl":"https://example.com/2_2","error":""}';
      const parsed = OnlinePageExtractor.parse(JSON.stringify(payload));
      expect(parsed.title).assertEqual('第二章');
      expect(parsed.previousUrl).assertEqual('https://example.com/1');
      expect(parsed.nextUrl).assertEqual('https://example.com/3');
      expect(parsed.nextChapterUrl).assertEqual('https://example.com/3');
      expect(parsed.nextPageUrl).assertEqual('https://example.com/2_2');
    });
  });
}
