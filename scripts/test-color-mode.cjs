// Validate native UI theme resources without a device or an external connection.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const colors = (mode) => Object.fromEntries(JSON.parse(read(
  `entry/src/main/resources/${mode}/element/color.json`)).color.map(({ name, value }) => [name, value]));
const light = colors('base');
const dark = colors('dark');
const pages = ['Index', 'OnlineSearch', 'Browser', 'OnlineReader'].map((name) => ({
  name, source: read(`entry/src/main/ets/pages/${name}.ets`)
}));
let checks = 0;
const test = (name, callback) => { callback(); checks++; console.log(`PASS ${name}`); };
const luminance = (hex) => {
  assert.match(hex, /^#[\da-f]{6}$/i);
  const rgb = [1, 3, 5].map((index) => {
    const channel = parseInt(hex.slice(index, index + 2), 16) / 255;
    return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
};
const contrast = (foreground, background) => {
  const values = [luminance(foreground), luminance(background)].sort((a, b) => a - b);
  return (values[1] + 0.05) / (values[0] + 0.05);
};

test('every UI color has matching light and dark resources', () => {
  assert.deepEqual(Object.keys(light).sort(), Object.keys(dark).sort());
  for (const mode of ['base', 'dark']) {
    const entries = JSON.parse(read(`entry/src/main/resources/${mode}/element/color.json`)).color;
    assert.equal(new Set(entries.map(({ name }) => name)).size, entries.length);
  }
  for (const { name, source } of pages) {
    for (const match of source.matchAll(/\$r\('app\.color\.([^']+)'\)/g)) {
      assert.ok(light[match[1]] && dark[match[1]], `${name}: missing ${match[1]}`);
    }
  }
});

test('system dark mode uses black backgrounds and no light shelf wallpaper', () => {
  assert.equal(dark.ui_background, '#000000');
  assert.equal(dark.ui_page_background, '#000000');
  assert.equal(dark.start_window_background, '#000000');
  assert.match(pages[0].source, /\.opacity\(this\.systemDarkMode \? 0 : this\.backgroundOpacity\)/);
  for (const { name, source } of pages) {
    assert.doesNotMatch(source, /\.backgroundColor\('#(?:FFFFFF|F7FAF7|F7F4F1|F1F3EF)'\)/, name);
  }
});

test('all 11 input fields explicitly theme text, placeholder, caret and background', () => {
  let inputs = 0;
  for (const { name, source } of pages) {
    for (const match of source.matchAll(/\bText(?:Input|Area)\([\s\S]*?\.backgroundColor\([^\r\n]+\)/g)) {
      inputs++;
      assert.match(match[0], /\.fontColor\(\$r\('app\.color\.ui_text_primary'\)\)/, name);
      assert.match(match[0], /\.placeholderColor\(\$r\('app\.color\.ui_text_muted'\)\)/, name);
      assert.match(match[0], /\.caretColor\(\$r\('app\.color\.ui_text_accent'\)\)/, name);
    }
  }
  assert.equal(inputs, 11);
});

test('dark input text and placeholders have at least 4.5:1 contrast', () => {
  for (const background of ['ui_surface', 'ui_surface_subtle', 'ui_shelf_input']) {
    for (const foreground of ['ui_text_primary', 'ui_text_muted', 'ui_text_accent']) {
      assert.ok(contrast(dark[foreground], dark[background]) >= 4.5, `${foreground}/${background}`);
    }
  }
  for (const background of ['ui_accent', 'ui_browser_accent', 'ui_brand_background']) {
    assert.ok(contrast(dark.ui_text_on_accent, dark[background]) >= 4.5, background);
  }
});

test('both readers share reactive system mode and preserve saved theme settings', () => {
  for (const { source } of [pages[0], pages[3]]) {
    assert.match(source, /@StorageLink\('systemDarkMode'\)/);
    assert.match(source, /AppTheme\.readerBackground\(/);
    assert.match(source, /AppTheme\.readerTextColor\(/);
  }
  const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(ability, /onConfigurationUpdate\(newConfig: Configuration\)/);
  assert.match(ability, /this\.updateColorMode\(newConfig\)/);
  assert.match(ability, /AppStorage\.setOrCreate<boolean>\('systemDarkMode', dark\)/);
  assert.doesNotMatch(read('entry/src/main/ets/data/AppTheme.ets'), /LibraryStore|settings\./);
});

test('browser webpages follow system mode, including sites without dark CSS', () => {
  assert.match(pages[2].source, /\.darkMode\(WebDarkMode\.Auto\)/);
  assert.match(pages[2].source, /\.forceDarkAccess\(true\)/);
});

console.log(`${checks} color mode checks passed.`);
