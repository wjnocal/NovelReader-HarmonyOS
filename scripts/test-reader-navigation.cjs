// Native-reader integration checks. Hardware light rendering still needs device QA.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/Index.ets'), 'utf8')
  .replace(/\r\n/g, '\n');
const controls = source.split('private ReaderNavigationContents() {')[1].split('private ReaderPage() {')[0];
const handler = source.match(/private handleReaderNavigation\(index: number\): void \{([\s\S]*?)\n  \}\n/);
assert.ok(handler);
const hints = [];
const handle = vm.runInNewContext(`(function(index) {${handler[1].replace(/error: BusinessError/g, 'error')}\n})`, {
  promptAction: { openToast: ({ message }) => { hints.push(message); return Promise.resolve(); } },
  console: { warn: () => {} }
});
const newReader = () => {
  const actions = [];
  return {
    actions, readerControlsVisible: true, readerNavigationIndex: 0, chapterIndex: 5, readerPageIndex: 3,
    openCatalog: () => actions.push('catalog'),
    toggleBookmark: () => actions.push('bookmark'),
    openSettings: () => actions.push('settings')
  };
};
let checks = 0;
const test = (name, callback) => { callback(); checks++; console.log(`PASS ${name}`); };

test('reader footer uses API 26 native floating Tabs with the old official HDS implementation as fallback', () => {
  assert.match(controls, /HdsTabs\(\{ barPosition: BarPosition.End, index: this.readerNavigationIndex \}\)/);
  assert.match(controls, /if \(deviceInfo\.sdkApiVersion >= 26\) \{\s*Tabs\(/);
  assert.match(controls, /systemMaterial: this\.navigationGlass\.getMaterial\(\)/);
  assert.match(controls, /smallBarWidth: 320, mediumBarWidth: 420, largeBarWidth: 520/);
  assert.match(controls, /\} else \{\s*HdsTabs\(/);
  assert.equal((controls.match(/this\.ReaderNavigationContents\(\)/g) || []).length, 2);
  assert.equal((controls.match(/TabContent\(\)/g) || []).length, 4);
  assert.match(controls, /\.barOverlap\(true\)/);
  assert.match(controls, /\.barFloatingStyle\([\s\S]*systemMaterialEffect:/);
  assert.match(controls, /materialType: this\.navigationMaterialType/);
  assert.match(controls, /materialLevel: hdsMaterial\.MaterialLevel\.ADAPTIVE/);
  assert.match(controls, /thermoCtrl: true/);
  assert.doesNotMatch(controls, /backgroundColor|backgroundBlurStyle|linearGradient|\.border\(|shadow\(/);
});

test('all four original actions and reactive bookmark/read-mode labels remain available', () => {
  assert.match(controls, /sys\.symbol\.list_bullet'\), '目录'/);
  assert.match(controls, /this\.isCurrentBookmarked\(\) \? '已书签' : '书签'/);
  assert.match(controls, /this\.readerReadMode === 0 \? '长按标记' : '长按笔记'/);
  assert.match(controls, /sys\.symbol\.gearshape'\), '设置'/);
  assert.match(source, /private readerNavigationStyle[\s\S]*?LayoutMode\.VERTICAL/);
  assert.match(source, /marked \? \$r\('app\.color\.ui_text_accent'\) : \$r\('sys\.color\.font_primary'\)/);
});

test('catalog/bookmark/settings dispatch to existing operations without changing reading position', () => {
  const reader = newReader();
  for (const index of [0, 1, 3]) handle.call(reader, index);
  assert.deepEqual(reader.actions, ['catalog', 'bookmark', 'settings']);
  assert.equal(reader.chapterIndex, 5);
  assert.equal(reader.readerPageIndex, 3);
  assert.doesNotMatch(handler[1], /changeChapter|mainTab|currentBookId|readerPageIndex\s*=/);
});

test('tapping bookmark twice calls toggle twice even while the same native tab stays selected', () => {
  const reader = newReader();
  handle.call(reader, 1);
  handle.call(reader, 1);
  assert.deepEqual(reader.actions, ['bookmark', 'bookmark']);
  assert.match(controls, /\.onTabBarClick\(\(index: number\) => this\.handleReaderNavigation\(index\)\)/);
});

test('the long-press hint explains selection without creating an empty note or bookmark', () => {
  const reader = newReader();
  handle.call(reader, 2);
  assert.equal(hints.length, 1);
  assert.match(hints[0], /长按正文/);
  assert.deepEqual(reader.actions, []);
});

test('hidden footer rejects events and is excluded from touch and accessibility', () => {
  const reader = newReader();
  reader.readerControlsVisible = false;
  for (const index of [0, 1, 2, 3]) handle.call(reader, index);
  assert.deepEqual(reader.actions, []);
  assert.equal(hints.length, 1);
  assert.match(controls, /this\.readerControlsVisible \? HitTestMode\.Default : HitTestMode\.None/);
  assert.match(controls, /this\.readerControlsVisible \? 'auto' : 'no-hide-descendants'/);
  reader.readerControlsVisible = true;
  for (const index of [-1, 4]) handle.call(reader, index);
  assert.deepEqual(reader.actions, []);
});

test('floating footer follows viewport height, menu progress and bottom safe area', () => {
  assert.match(controls, /\.height\(132\)/);
  assert.match(controls, /\.safeAreaPadding\(\{ bottom: 8 \}\)/);
  assert.match(controls, /barSideMargin: 16/);
  assert.match(controls, /barBottomMargin: 12/);
  assert.match(controls, /\.opacity\(this\.readerControlsProgress\)/);
  assert.match(controls, /\(1 - this\.readerControlsProgress\) \* 132/);
  assert.match(controls, /Math\.max\(0, this\.readerViewportHeight - 132\)/);
  assert.doesNotMatch(controls, /readerViewportHeight\s*=|rebuildReaderPages/);
});

console.log(`${checks} reader navigation checks passed.`);
