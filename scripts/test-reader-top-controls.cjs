// SDK-independent regression checks; material appearance still requires HarmonyOS device QA.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const source = read('entry/src/main/ets/pages/Index.ets');
const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
const material = read('entry/src/main/ets/components/ReaderControlMaterial.ets');
const top = source.split('private ReaderTopControls() {')[1].split('private ReaderBottomControls() {')[0];
const floating = source.split('private ReaderFloatingControl(title: boolean) {')[1].split('private ReaderTopControls() {')[0];
const title = source.split('private ReaderBookTitle() {')[1].split('private ReaderFloatingLabel(')[0];
let checks = 0;
const test = (name, callback) => { callback(); checks++; console.log(`PASS ${name}`); };
const method = (name) => {
  const match = source.match(new RegExp(`private ${name}\\(\\): number \\{([\\s\\S]*?)\\n  \\}`));
  assert.ok(match, name);
  return vm.runInNewContext(`(function() {${match[1]}\n})`);
};

test('API 26 is targeted while the API 23 installation minimum is preserved', () => {
  assert.match(read('build-profile.json5'), /"targetSdkVersion": "26\.0\.0"/);
  assert.match(read('build-profile.json5'), /"compatibleSdkVersion": "6\.1\.0\(23\)"/);
  for (const file of ['oh-package.json5', 'hvigor/hvigor-config.json5']) {
    assert.match(read(file), /"modelVersion": "26\.0\.0"/);
  }
});

test('return and title reuse the working native floating bar material and have no emphasized blue button', () => {
  assert.match(source, /new ReaderControlMaterial\(true\)/);
  assert.match(top, /this\.ReaderFloatingControl\(false\)/);
  assert.match(top, /this\.ReaderFloatingControl\(true\)/);
  assert.match(floating, /if \(deviceInfo\.sdkApiVersion >= 26\) \{\s*\/\/[^\n]+\n\s*Tabs\(/);
  assert.match(floating, /systemMaterial: this\.navigationGlass\.getMaterial\(\)/);
  assert.equal((floating.match(/TabContent\(\)/g) || []).length, 1);
  assert.match(floating, /\.tabBar\(this\.ReaderFloatingLabel\(title\)\)/);
  assert.match(floating, /\.barHeight\(48, true\)/);
  assert.match(floating, /\.buttonStyle\(ButtonStyleMode\.NORMAL\)/);
  assert.doesNotMatch(floating, /EMPHASIZED|\.attributeModifier\(|\.systemMaterial\(/);
  const native = floating.split('} else {')[0];
  assert.doesNotMatch(native, /Button\(|backgroundColor|backgroundBlurStyle|linearGradient|shadow\(/);
  assert.match(source, /SymbolGlyph\(\$r\('sys\.symbol\.chevron_left'\)\)/);
  assert.match(floating, /\.backgroundColor\(\$r\('app\.color\.ui_surface'\)\)/);
});

test('native floating frames have no surrounding margin or footer mask', () => {
  const match = floating.match(/\.barFloatingStyle\(\{([\s\S]*?)\n        \}\)/);
  assert.ok(match);
  const style = vm.runInNewContext(`(function(title) { return {${match[1]}}; })`, { Color: { Transparent: 'transparent' } });
  const reader = { readerTitleWidth: () => 200, navigationGlass: { getMaterial: () => 'native-material' } };
  for (const title of [false, true]) {
    const config = style.call(reader, title);
    for (const value of Object.values(config.barWidth)) assert.equal(value, title ? 200 : 48);
    assert.equal(config.barSideMargin, 0);
    assert.equal(config.barBottomMargin, 0);
    assert.equal(config.maskHeight, 0);
    assert.equal(config.maskColor, 'transparent');
    assert.equal(config.systemMaterial, 'native-material');
  }
  assert.match(floating, /\.width\(title \? this\.readerTitleWidth\(\) : 48\)/);
  assert.doesNotMatch(floating, /\.height\(64\)|\+ 16/);
});

test('each top glass control clips haze to its own circle/capsule without moving its visible position', () => {
  assert.match(floating, /\.width\(title \? this\.readerTitleWidth\(\) : 48\)\s*\.height\(48\)\s*\.borderRadius\(24\)\s*\.clip\(true\)/);
  assert.match(top, /\.width\(48\)\s*\.height\(48\)\s*\.position\(\{ x: 16, y: this\.readerControlsTop\(\) \}\)/);
  assert.match(top, /\.width\(this\.readerTitleWidth\(\)\)\s*\.height\(48\)\s*\.position\(\{ x: \(this\.readerViewportWidth - this\.readerTitleWidth\(\)\) \/ 2,\s*y: this\.readerControlsTop\(\) \}\)/);
  assert.doesNotMatch(top, /readerControlsTop\(\) - 8|readerTitleWidth\(\) \+ 16/);
});

test('book title remains screen-centered with clearance from the back button at phone and tablet widths', () => {
  const width = method('readerTitleWidth');
  for (const viewport of [240, 320, 360, 412, 600, 900, 1280]) {
    const capsule = width.call({ readerViewportWidth: viewport });
    const left = (viewport - capsule) / 2;
    assert.ok(capsule >= 48 && capsule <= 280);
    assert.ok(left >= 16 + 48 + 12);
    assert.equal(left + capsule / 2, viewport / 2);
  }
  assert.match(top, /\(this\.readerViewportWidth - this\.readerTitleWidth\(\)\) \/ 2/);
  assert.match(title, /Text\(this\.currentBookTitle\(\)\)[\s\S]*?\.maxLines\(1\)[\s\S]*?TextOverflow\.Ellipsis/);
  assert.match(title, /sys\.color\.font_primary/);
  assert.match(title, /sys\.color\.font_secondary/);
});

test('controls and pagination react to the actual camera inset in pixels, including window changes', () => {
  const position = method('readerControlsTop');
  const reader = { readerTopInsetPx: 150, getUIContext: () => ({ px2vp: (value) => value / 3 }) };
  assert.equal(position.call(reader), 58);
  reader.readerTopInsetPx = 0;
  assert.equal(position.call(reader), 32);
  assert.match(ability, /getWindowAvoidArea\(window\.AvoidAreaType\.TYPE_CUTOUT\)/);
  assert.match(ability, /cutout\.top \+ cutout\.height/);
  assert.match(ability, /on\('avoidAreaChange', this\.onAvoidAreaChanged\)/);
  assert.match(ability, /off\('avoidAreaChange', this\.onAvoidAreaChanged\)/);
  assert.match(source, /@Watch\('onReaderTopInsetChanged'\)/);
  assert.match(source, /private onReaderTopInsetChanged[\s\S]*?this\.rebuildReaderPages\(\)/);
  assert.match(source, /private readerSafeTop[\s\S]*?this\.readerControlsTop\(\) \+ 12/);
});

test('menus overlay the book without reserving button height or repaginating on visibility changes', () => {
  const safeTop = method('readerSafeTop');
  for (const controlsTop of [32, 48, 64, 80]) {
    const reader = { readerControlsTop: () => controlsTop, readerTextSize: 19,
      readerLineHeight: 1.65, readerPageMargin: 22 };
    const padding = safeTop.call(reader);
    const expected = Math.max(56, controlsTop + 12, Math.round(19 * 1.65 + 22 + 12));
    assert.equal(padding, expected);
    assert.ok(padding < controlsTop + 48);
  }
  const paddingSource = source.split('private readerSafeTop(): number {')[1].split('private onReaderTopInsetChanged')[0];
  assert.doesNotMatch(paddingSource, /readerControlsVisible|readerControlsProgress/);
  assert.match(source, /usableHeight = Math\.max\(240, this\.readerViewportHeight - this\.readerSafeTop\(\) - 66\)/);
  assert.match(source, /top: this\.readerSafeTop\(\), bottom: 60/);
});

test('hidden controls do not intercept reading touches or accessibility focus', () => {
  assert.match(top, /this\.readerControlsVisible \? HitTestMode\.Transparent : HitTestMode\.None/);
  assert.match(top, /this\.readerControlsVisible \? 'auto' : 'no-hide-descendants'/);
  assert.match(floating, /this\.readerControlsVisible \? HitTestMode\.Default : HitTestMode\.None/);
  assert.match(top, /\.opacity\(this\.readerControlsProgress\)/);
  assert.match(top, /\(this\.readerControlsProgress - 1\) \* \(this\.readerControlsTop\(\) \+ 60\)/);
});

test('title clicks consume native light feedback without navigation, state writes, toast or reading actions', () => {
  const match = source.match(/private handleReaderTopControl\(title: boolean\): void \{([\s\S]*?)\n  \}/);
  assert.ok(match);
  const handler = vm.runInNewContext(`(function(title) {${match[1]}\n})`);
  let closes = 0;
  const reader = { readerControlsVisible: true, chapterIndex: 2, readerPageIndex: 4, closeReader: () => { closes++; } };
  for (let index = 0; index < 5; index++) handler.call(reader, true);
  assert.equal(closes, 0);
  assert.equal(reader.chapterIndex, 2);
  assert.equal(reader.readerPageIndex, 4);
  assert.equal(reader.readerControlsVisible, true);
  handler.call(reader, false);
  assert.equal(closes, 1);
  reader.readerControlsVisible = false;
  handler.call(reader, false);
  assert.equal(closes, 1);
  assert.doesNotMatch(match[1], /promptAction|toggleReader|changeChapter|rebuildReader|=\s*[^=]/);
  assert.match(floating, /\.onTabBarClick\(\(\) => this\.handleReaderTopControl\(title\)\)/);
  assert.match(floating, /\.onClick\(\(\) => this\.handleReaderTopControl\(title\)\)/);
});

const loadMaterial = (api, supported = true, disabled = false, broken = false) => {
  let queried = 0;
  const transformed = material.replace(/^import.*\n/gm, '')
    .replace('export class ReaderControlMaterial', 'class ReaderControlMaterial')
    .replace('private material', 'material')
    .replace(/: uiMaterial\.ImmersiveMaterial \| undefined/g, '')
    .replace('interactive: boolean', 'interactive')
    .replace('instance: CommonAttribute', 'instance').replace('): void {', ') {');
  const native = {
    isImmersiveMaterialSupported: () => {
      queried++;
      if (broken) throw new Error('unavailable');
      return supported;
    },
    getMaterialInfo: () => ({ state: disabled ? 2 : 0 }),
    MaterialState: { DISABLE: 2 },
    ImmersiveStyle: { ULTRA_THIN: 0 },
    ImmersiveMaterial: class { constructor(options) { this.options = options; } }
  };
  const Material = vm.runInNewContext(`${transformed}\nReaderControlMaterial`, {
    deviceInfo: { sdkApiVersion: api }, uiMaterial: api >= 26 ? native : undefined,
    $r: (name) => name, console: { warn: () => {} }
  });
  return { Material, queries: () => queried };
};

test('HarmonyOS 7 supplies genuine ultra-thin material with the requested native interaction options', () => {
  const { Material } = loadMaterial(26);
  for (const interactive of [true, false]) {
    const rendered = new Material(interactive).getMaterial();
    assert.equal(rendered.options.style, 0);
    assert.equal(rendered.options.colorInvert, true);
    assert.equal(rendered.options.interactive, interactive);
    assert.equal(rendered.options.lightEffect === null, !interactive);
  }
});

test('older systems never access the API 26 module and top rendering gates the new attribute', () => {
  for (const api of [23, 24, 25]) {
    const { Material, queries } = loadMaterial(api);
    const rendered = new Material(true).getMaterial();
    assert.equal(queries(), 0);
    assert.equal(rendered, undefined);
  }
  assert.match(floating, /if \(deviceInfo\.sdkApiVersion >= 26\)/);
});

test('disabled, unsupported, and failed material capabilities retain a readable themed fallback', () => {
  for (const capabilities of [[false, false, false], [true, true, false], [true, false, true]]) {
    const { Material } = loadMaterial(26, ...capabilities);
    assert.equal(new Material(false).getMaterial(), undefined);
  }
});

console.log(`${checks} reader top control checks passed.`);
