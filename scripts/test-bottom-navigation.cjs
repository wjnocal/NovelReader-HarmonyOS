// Verify Huawei's native floating tabs integration; this does not replace device visual QA.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const source = read('entry/src/main/ets/pages/Index.ets');
let checks = 0;
const test = (name, callback) => {
  callback();
  checks++;
  console.log(`PASS ${name}`);
};

const switchMethod = source.match(/private switchMainTab\(tab: string\): void \{([\s\S]*?)\n  \}\n/);
assert.ok(switchMethod);
const switchTab = vm.runInNewContext(`(function(tab) {${switchMethod[1]}\n})`);
const newPage = () => {
  const calls = [];
  return { mainTab: 'shelf', calls, mainTabsController: { changeIndex: (index) => calls.push(index) } };
};

test('programmatic navigation immediately updates the official tab controller', () => {
  const page = newPage();
  switchTab.call(page, 'home');
  assert.equal(page.mainTab, 'home');
  assert.deepEqual(page.calls, [1]);
  switchTab.call(page, 'shelf');
  assert.equal(page.mainTab, 'shelf');
  assert.deepEqual(page.calls, [1, 0]);
});

test('rapid and repeated navigation has no delayed callbacks to overwrite state', () => {
  const page = newPage();
  for (const tab of ['shelf', 'home', 'home', 'shelf', 'home', 'shelf']) switchTab.call(page, tab);
  assert.equal(page.mainTab, 'shelf');
  assert.deepEqual(page.calls, [1, 0, 1, 0]);
  assert.doesNotMatch(switchMethod[1], /setTimeout|animateTo/);
});

const material = source.match(/private updateNavigationMaterial\(\): void \{([\s\S]*?)\n  \}\n/);
assert.ok(material);
const materialType = { ADAPTIVE: 100, IMMERSIVE: 101 };
const materialUpdater = (query) => vm.runInNewContext(`(function() {${material[1]}\n})`, {
  hdsMaterial: { MaterialType: materialType, getSystemMaterialTypes: query },
  console: { warn: () => {} }
});

test('supported devices use genuine IMMERSIVE material', () => {
  const page = {};
  materialUpdater(() => [materialType.IMMERSIVE]).call(page);
  assert.equal(page.navigationMaterialType, materialType.IMMERSIVE);
});

test('unsupported devices and capability errors use the official adaptive fallback', () => {
  for (const query of [() => [], () => { throw new Error('Unavailable'); }]) {
    const page = {};
    materialUpdater(query).call(page);
    assert.equal(page.navigationMaterialType, materialType.ADAPTIVE);
  }
});

test('API 26 navigation uses native Tabs and uiMaterial with legacy HdsTabs only as the old-system fallback', () => {
  const navigation = source.split('private MainNavigationContents() {')[1].split('private ShelfPage() {')[0];
  assert.match(source, /import \{ HdsTabs, HdsTabsController, hdsMaterial \} from '@kit\.UIDesignKit'/);
  assert.match(navigation, /HdsTabs\(\{/);
  assert.match(navigation, /if \(deviceInfo\.sdkApiVersion >= 26\) \{\s*Tabs\(\{/);
  assert.match(navigation, /systemMaterial: this\.navigationGlass\.getMaterial\(\)/);
  assert.match(navigation, /smallBarWidth: 280, mediumBarWidth: 360, largeBarWidth: 440/);
  assert.match(navigation, /\} else \{[\s\S]*?HdsTabs\(\{/);
  assert.equal((navigation.match(/this\.MainNavigationContents\(\)/g) || []).length, 2);
  assert.equal((navigation.match(/TabContent\(\)/g) || []).length, 2);
  assert.match(navigation, /navigationBarStyle\(\$r\('sys\.symbol\.bookshelf'\), '书架'\)/);
  assert.match(navigation, /navigationBarStyle\(\$r\('sys\.symbol\.house'\), '主页'\)/);
  assert.match(source, /BottomTabBarStyle\.of\(/);
  assert.match(navigation, /\.barOverlap\(true\)/);
  assert.match(navigation, /\.barPosition\(BarPosition\.End\)/);
  assert.match(navigation, /\.vertical\(false\)/);
  assert.match(navigation, /\.barFloatingStyle\([\s\S]*systemMaterialEffect:/);
  assert.match(navigation, /materialType: this\.navigationMaterialType/);
  assert.match(navigation, /materialLevel: hdsMaterial\.MaterialLevel\.ADAPTIVE/);
  assert.match(navigation, /thermoCtrl: true/);
  assert.doesNotMatch(navigation, /backgroundBlurStyle|linearGradient|shadow\(|borderRadius|barBackgroundColor/);
  assert.doesNotMatch(source, /ImmersiveNavigation|navigationWidth|navigationTab|pageProgress|ui_nav_/);
});

test('native selection updates app state and initial index restores the active page', () => {
  assert.match(source, /index: this\.mainTab === 'shelf' \? 0 : 1/);
  assert.match(source, /\.onChange\(\(index: number\) => \{\s*this\.mainTab = index === 0 \? 'shelf' : 'home'/);
});

test('both pages retain camera and gesture safe areas and scrollable navigation clearance', () => {
  const shelf = source.split('private BookshelfContent() {')[1].split('private ShelfPage() {')[0];
  const home = source.split('private HomePage() {')[1].split('private HomeStat(')[0];
  assert.match(shelf, /GridItem\(\) \{\s*Column\(\)\.height\(100\)/);
  assert.match(shelf, /\.contentEndOffset\(100\)/);
  assert.match(home, /\.padding\(\{ top: 28, bottom: 100 \}\)/);
  assert.equal((source.match(/\.safeAreaPadding\(\{ top: 8 \}\)/g) || []).length, 2);
  assert.match(source, /\.safeAreaPadding\(\{ bottom: 8 \}\)/);
  assert.match(source, /barBottomMargin: 12/);
});

test('discarded custom glass colors are absent in both color modes', () => {
  for (const mode of ['base', 'dark']) {
    const entries = JSON.parse(read(`entry/src/main/resources/${mode}/element/color.json`)).color;
    assert.ok(entries.every(({ name }) => !name.startsWith('ui_nav_')));
  }
});

console.log(`${checks} official bottom navigation checks passed.`);
