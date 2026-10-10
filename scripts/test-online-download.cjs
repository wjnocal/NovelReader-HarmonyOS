/* Runs the real ArkTS download/storage/parser code with local HTTP and filesystem adapters.
 * Usage: node scripts/test-online-download.cjs
 * Set TYPESCRIPT_PATH when TypeScript is not installed in Node or DevEco Studio.
 */
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const crypto = require('node:crypto');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const candidates = [process.env.TYPESCRIPT_PATH, 'typescript',
  'F:/devecostudio-windows-6.1.1.290/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript'];
let ts;
for (const candidate of candidates.filter(Boolean)) {
  try { ts = require(candidate); break; } catch (_) { }
}
if (!ts) throw new Error('Set TYPESCRIPT_PATH to your TypeScript installation.');

const coreFs = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4, READ_ONLY: 8 },
  accessSync: (file) => fs.existsSync(file),
  mkdirSync: (file, recursive) => fs.mkdirSync(file, { recursive }),
  readTextSync: (file) => fs.readFileSync(file, 'utf8'),
  openSync: (file, mode) => ({ fd: fs.openSync(file, mode & 8 ? 'r' : 'w') }),
  closeSync: (file) => fs.closeSync(typeof file === 'number' ? file : file.fd),
  writeSync: (fd, value) => fs.writeSync(fd, typeof value === 'string' ? value : Buffer.from(value)),
  readSync: (fd, value) => fs.readSync(fd, Buffer.from(value), 0, value.byteLength, null),
  renameSync: fs.renameSync, copyFileSync: fs.copyFileSync,
  listFileSync: fs.readdirSync, unlinkSync: fs.unlinkSync, rmdirSync: fs.rmdirSync,
  statSync: (file) => {
    const stat = fs.statSync(file);
    return { size: stat.size, mtime: stat.mtimeMs / 1000, isDirectory: () => stat.isDirectory() };
  }
};
const storage = new Map();
global.AppStorage = { get: (key) => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) };
const kits = {
  '@kit.AbilityKit': {}, '@kit.BasicServicesKit': {},
  '@kit.ArkTS': { util: {
    TextDecoder: { create: (encoding) => ({ decodeToString: (bytes) => new TextDecoder(encoding).decode(bytes) }) },
    TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } }
  } },
  '@kit.CoreFileKit': { fileIo: coreFs, hash: {
    hash: async (file) => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')
  } },
  '@kit.NetworkKit': { http: {
    RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { ARRAY_BUFFER: 1 },
    createHttp: () => {
      let active;
      return {
        request: (url, options) => new Promise((resolve, reject) => {
          if (scenario.unsettledSearch && url.includes('/searchHang')) {
            const key = new URL(url).pathname;
            counts.set(key, (counts.get(key) ?? 0) + 1);
            // Simulate a platform request whose promise stays pending even after destroy().
            return;
          }
          active = http.request(url, { method: options.method, headers: options.header }, (response) => {
            const chunks = [];
            response.on('data', (chunk) => chunks.push(chunk));
            response.on('end', () => {
              const bytes = Buffer.concat(chunks);
              resolve({ responseCode: response.statusCode, header: response.headers,
                result: bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) });
            });
            response.on('error', reject);
          });
          active.setTimeout(options.readTimeout, () => active.destroy(new Error('timeout')));
          active.on('error', reject);
          active.end(options.extraData);
        }),
        destroy: () => active?.destroy()
      };
    }
  } }
};
const moduleCache = new Map();
function load(file) {
  file = path.resolve(file.endsWith('.ets') ? file : `${file}.ets`);
  if (moduleCache.has(file)) return moduleCache.get(file).exports;
  const module = { exports: {} };
  moduleCache.set(file, module);
  const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const localRequire = (id) => id.startsWith('.') ? load(path.resolve(path.dirname(file), id)) :
    kits[id] ?? require(id);
  vm.runInThisContext(`(function(require,module,exports){${output}\n})`, { filename: file })
    (localRequire, module, module.exports);
  return module.exports;
}

const root = path.resolve(__dirname, '..');
const data = path.join(root, 'entry/src/main/ets/data');
const { OnlineBookService, OnlineDownloadCancelToken, OnlineSearchOptions } = load(path.join(data, 'OnlineBookService'));
const { LibraryStore } = load(path.join(data, 'LibraryStore'));
const { OnlineChapterCache } = load(path.join(data, 'OnlineChapterCache'));
const { OnlineDownloadState } = load(path.join(data, 'OnlineDownloadState'));
const { BookRecord } = load(path.join(root, 'entry/src/main/ets/model/Models'));
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
let origin;
let scenario = {};
const counts = new Map();
const headers = [];
const server = http.createServer((request, response) => {
  const url = new URL(request.url, origin);
  counts.set(url.pathname, (counts.get(url.pathname) ?? 0) + 1);
  headers.push({ path: url.pathname, headers: request.headers });
  const end = (body, code = 200) => {
    if (!response.destroyed) { response.writeHead(code, { 'Content-Type': 'text/html; charset=utf-8' }); response.end(body); }
  };
  if (url.pathname === '/book') {
    return end('<h1>测试小说</h1><meta property="og:novel:author" content="测试作者">' +
      '<div id="toc">' + Array.from({ length: 3 }, (_, i) => `<a href="/chapter${i + 1}">第${i + 1}章</a>`).join('') + '</div>');
  }
  if (url.pathname.startsWith('/search')) {
    if (url.pathname === '/searchMissing') return end('missing', 404);
    if (url.pathname === '/searchPaged') return end('<div class="result"><a href="/book">测试小说</a></div>' +
      '<a id="next" href="/searchMissing">下一页</a>');
    if (url.pathname === '/searchSlowPages') return end('<div class="result"><a href="/book">测试小说</a></div>' +
      '<a id="next" href="/searchSlowSecond">下一页</a>');
    if (url.pathname === '/searchSlowSecond') return setTimeout(() => end(
      '<div class="result"><a href="/book2">第二本小说</a></div>'), 250);
    return setTimeout(() => end('<div class="result"><a href="/book">测试小说</a></div>'),
      url.pathname === '/searchA' ? 60 : 5);
  }
  const index = Number(url.pathname.match(/^\/chapter(\d)/)?.[1]);
  if (!index) return end('missing', 404);
  if (scenario.legacyCharset && index === 1) {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=iso-8859-1' });
    return response.end(Buffer.from('<div id="body">caf\u00e9</div>', 'latin1'));
  }
  if (scenario.status === 403 && index === 1) return end('forbidden', 403);
  if (scenario.rateLimit && index === 1 && counts.get('/chapter1') === 1) {
    response.writeHead(429, { 'Retry-After': '1' }); return response.end('limited');
  }
  if (scenario.failSecond && index === 2) return setTimeout(() => end('error', 503), 120);
  if (scenario.failThird && index === 3) return setTimeout(() => end('error', 503), 120);
  if (scenario.cancel && index === 2) return setTimeout(() => end('<div id="body">second</div>'), 1500);
  if (scenario.multiPage && index === 1) {
    const page = Number(url.searchParams.get('page') ?? 1);
    if (scenario.failPage === page) return end('missing', 404);
    const next = page < 12 ? `/chapter1?page=${page + 1}` : '/chapter2';
    return end(`<div id="body">页-${page}</div><a id="next" href="${next}">下一页</a>`);
  }
  setTimeout(() => end(`<div id="body">正文-${index}</div>`), index === 1 ? 35 : index === 2 ? 80 : 5);
});

function fixture(temp) {
  fs.mkdirSync(path.join(temp, 'files'), { recursive: true });
  fs.mkdirSync(path.join(temp, 'cache'), { recursive: true });
  const source = {
    id: 'test', name: '本地测试', baseUrl: `${origin}/`, enabled: true,
    search: { url: `${origin}/searchA`, result: '.result', bookName: 'a', cookies: 'test=1' },
    book: { bookName: 'h1', author: 'meta[property="og:novel:author"]' },
    toc: { item: '#toc a' }, chapter: { content: '#body', nextPage: '#next' },
    crawl: { minIntervalMillis: 0, maxIntervalMillis: 0, maxRetries: 0, timeoutMillis: 3000, concurrency: 3 }
  };
  const context = { filesDir: path.join(temp, 'files'), cacheDir: path.join(temp, 'cache'),
    resourceManager: { getRawFileContent: async () => new TextEncoder().encode(JSON.stringify([source])) } };
  const result = { sourceId: 'test', sourceName: '本地测试', bookName: '测试小说', author: '测试作者', category: '', url: `${origin}/book` };
  return { source, context, result, service: new OnlineBookService(context) };
}
async function rejected(action, pattern) {
  await assert.rejects(action, pattern);
}
async function test(name, action) {
  scenario = {}; counts.clear(); headers.length = 0; storage.clear();
  OnlineBookService.nextRequestAt.clear(); OnlineBookService.backoffUntil.clear();
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'novelreader-download-test-'));
  try { await action(fixture(temp)); console.log(`PASS ${name}`); }
  finally { fs.rmSync(temp, { recursive: true, force: true }); }
}

(async () => {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  try {
    await test('first chapter is readable before completion; progress and notes survive appends', async ({ service, context, result }) => {
      let firstReadable = false;
      const book = await service.downloadToLibrary(result, 'txt', undefined, new OnlineDownloadCancelToken(), (partial) => {
        if (firstReadable) return;
        firstReadable = true;
        assert.equal(partial.downloadComplete, false);
        assert.equal(LibraryStore.loadChapters(partial).length, 1);
        const reading = LibraryStore.load(context);
        reading.books[0].currentPageIndex = 4;
        reading.books[0].scrollOffset = 89;
        reading.books[0].title = '自定义书名';
        reading.notes.push({ id: 'note-1', bookId: partial.id, chapterIndex: 0, selectedText: '正文', noteText: '测试笔记' });
        LibraryStore.save(context, reading);
      });
      assert.equal(book.downloadComplete, true);
      assert.equal(book.currentPageIndex, 4);
      assert.equal(book.scrollOffset, 89);
      assert.equal(book.title, '自定义书名');
      assert.equal(LibraryStore.load(context).notes[0].noteText, '测试笔记');
      assert.deepEqual(LibraryStore.loadChapters(book).map((chapter) => chapter.content), ['正文-1', '正文-2', '正文-3']);
      const content = fs.readFileSync(book.originalFilePath, 'utf8');
      assert.equal((content.match(/第1章/g) ?? []).length, 1);
    });

    await test('failure preserves readable prefix; retry reuses complete cached chapters', async ({ service, context, result }) => {
      scenario.failSecond = true;
      await rejected(() => service.downloadToLibrary(result), /下载失败/);
      const partial = LibraryStore.load(context).books[0];
      assert.equal(partial.downloadComplete, false);
      assert.equal(partial.totalChapters, 3);
      assert.equal(LibraryStore.loadChapters(partial).length, 1);
      const firstCount = counts.get('/chapter1');
      const thirdCount = counts.get('/chapter3');
      scenario.failSecond = false; OnlineBookService.backoffUntil.clear();
      const finished = await new OnlineBookService(context).downloadToLibrary(result);
      assert.equal(finished.id, partial.id);
      assert.equal(counts.get('/chapter1'), firstCount);
      assert.equal(counts.get('/chapter3'), thirdCount);
      assert.equal(finished.availableChapters, 3);
    });

    await test('cancel aborts in-flight HTTP and retains readable chapters', async ({ service, context, result }) => {
      scenario.cancel = true;
      const token = new OnlineDownloadCancelToken();
      let cancelledAt = 0;
      const promise = service.downloadToLibrary(result, 'txt', undefined, token, () => {
        if (cancelledAt) return;
        cancelledAt = Date.now(); token.cancel();
      });
      await rejected(() => promise, /取消/);
      assert.ok(Date.now() - cancelledAt < 500);
      assert.equal(LibraryStore.loadChapters(LibraryStore.load(context).books[0]).length, 1);
      await delay(150);
      assert.equal(LibraryStore.load(context).books[0].downloadComplete, false);
    });

    await test('resuming never shrinks a readable prefix or clamps its saved position', async ({ service, context, result }) => {
      scenario.failThird = true;
      await rejected(() => service.downloadToLibrary(result), /下载失败/);
      const reading = LibraryStore.load(context);
      assert.equal(LibraryStore.loadChapters(reading.books[0]).length, 2);
      reading.books[0].currentChapterIndex = 1;
      reading.books[0].currentPageIndex = 6;
      LibraryStore.save(context, reading);
      const token = new OnlineDownloadCancelToken();
      await rejected(() => new OnlineBookService(context).downloadToLibrary(result, 'txt', undefined, token,
        () => token.cancel()), /取消/);
      const retained = LibraryStore.load(context).books[0];
      assert.equal(LibraryStore.loadChapters(retained).length, 2);
      assert.equal(retained.currentChapterIndex, 1);
      assert.equal(retained.currentPageIndex, 6);
    });

    await test('twelve chapter pages are merged without crossing the known chapter boundary', async ({ service, context, result }) => {
      scenario.multiPage = true;
      const book = await service.downloadToLibrary(result, 'epub');
      const chapters = LibraryStore.loadChapters(book);
      assert.equal(chapters[0].content.split('\n\n').length, 12);
      assert.ok(!chapters[0].content.includes('正文-2'));
      assert.equal(fs.readFileSync(book.originalFilePath).readUInt32LE(0), 0x04034b50);
    });

    await test('missing middle page never publishes or caches a truncated chapter', async ({ service, context, result }) => {
      scenario.multiPage = true; scenario.failPage = 6;
      await rejected(() => service.downloadToLibrary(result), /HTTP 404/);
      assert.equal(LibraryStore.load(context).books.length, 0);
      const before = counts.get('/chapter1');
      scenario.failPage = 0;
      await new OnlineBookService(context).downloadToLibrary(result);
      assert.ok(counts.get('/chapter1') > before);
    });

    await test('resume rejects changed format and preserves the existing partial book', async ({ service, context, result }) => {
      scenario.failSecond = true;
      await rejected(() => service.downloadToLibrary(result), /下载失败/);
      const before = LibraryStore.load(context).books[0];
      await rejected(() => new OnlineBookService(context).downloadToLibrary(result, 'epub'), /已变化/);
      assert.equal(LibraryStore.load(context).books[0].fileType, 'txt');
      assert.equal(LibraryStore.loadChapters(before).length, 1);
    });

    await test('cache verifies hashes and rule identity; damaged entries are ignored', async ({ context }) => {
      const cache = new OnlineChapterCache(context);
      await cache.write('chapter|rule-v1', '完整正文');
      assert.equal(await cache.read('chapter|rule-v1'), '完整正文');
      assert.equal(await cache.read('chapter|rule-v2'), '');
      fs.writeFileSync(path.join(context.cacheDir, 'online_chapters', `${OnlineDownloadState.key('chapter|rule-v1')}.txt`), 'damaged');
      assert.equal(await cache.read('chapter|rule-v1'), '');
    });

    await test('403 is not retried and Referer omits the root trailing slash', async ({ service, result }) => {
      scenario.status = 403;
      await rejected(() => service.downloadToLibrary(result), /HTTP 403/);
      assert.equal(counts.get('/chapter1'), 1);
      assert.equal(headers[0].headers.referer, origin);
    });

    await test('HTTP charset declarations preserve non-UTF8 text', async ({ service, result }) => {
      scenario.legacyCharset = true;
      const book = await service.downloadToLibrary(result);
      assert.equal(LibraryStore.loadChapters(book)[0].content, 'caf\u00e9');
    });

    await test('429 respects Retry-After before retry', async ({ context, source, result }) => {
      scenario.rateLimit = true; source.crawl.maxRetries = 1;
      const start = Date.now();
      await new OnlineBookService(context).downloadToLibrary(result);
      assert.equal(counts.get('/chapter1'), 2);
      assert.ok(Date.now() - start >= 1000);
    });

    await test('concurrent source searches retain configured order and search cookies', async ({ context, source }) => {
      const other = { ...source, id: 'second', name: '第二书源', search: { ...source.search, url: `${origin}/searchB` } };
      context.resourceManager.getRawFileContent = async () => new TextEncoder().encode(JSON.stringify([source, other]));
      const results = await new OnlineBookService(context).search('测试');
      assert.deepEqual(results.map((result) => result.sourceId), ['test', 'second']);
      assert.equal(headers.find((item) => item.path === '/searchA').headers.cookie, 'test=1');
    });

    await test('stale reading snapshots cannot overwrite new download metadata or resurrect a deleted book', async ({ context }) => {
      const book = new BookRecord();
      book.id = 'partial'; book.syncId = 'partial-sync'; book.downloadKey = 'job';
      book.downloadRevision = 1; book.downloadComplete = false; book.availableChapters = 1;
      const initial = LibraryStore.load(context); initial.books.push(book); LibraryStore.save(context, initial);
      const stale = LibraryStore.load(context);
      const latest = LibraryStore.load(context); latest.books[0].availableChapters = 3; latest.books[0].downloadRevision = 2;
      LibraryStore.save(context, latest);
      stale.books[0].currentPageIndex = 9; LibraryStore.save(context, stale);
      assert.equal(LibraryStore.load(context).books[0].availableChapters, 3);
      assert.equal(LibraryStore.load(context).books[0].currentPageIndex, 9);
      const removed = LibraryStore.load(context); removed.books = [];
      removed.syncTombstones.push({ type: 'book', syncId: book.syncId, deletedAt: Date.now() });
      LibraryStore.save(context, removed);
      assert.equal(LibraryStore.load(context).books.length, 0);
    });
    await test('a single 404 search ends immediately without retry and identifies the failed source', async ({ context, source }) => {
      source.search.url = `${origin}/searchMissing`; source.crawl.maxRetries = 2;
      const start = Date.now();
      await rejected(() => new OnlineBookService(context).search('测试'), /本地测试.*HTTP 404/);
      assert.equal(counts.get('/searchMissing'), 1);
      assert.ok(Date.now() - start < 500);
    });

    await test('404 sources do not block incremental results while a stuck request is bounded', async ({ context, source }) => {
      scenario.unsettledSearch = true;
      source.search.url = `${origin}/searchMissing`;
      const hanging = { ...source, id: 'hang', name: '无响应书源', search: { ...source.search, url: `${origin}/searchHang` } };
      const good = { ...source, id: 'good', name: '正常书源', search: { ...source.search, url: `${origin}/searchB` } };
      context.resourceManager.getRawFileContent = async () => new TextEncoder().encode(JSON.stringify([source, hanging, good]));
      const options = new OnlineSearchOptions(); options.requestTimeoutMillis = 100;
      const messages = [];
      let publishedAt = 0;
      const results = await new OnlineBookService(context, options).search('测试', (message) => messages.push(message),
        undefined, (results) => { if (results.length && !publishedAt) publishedAt = Date.now(); });
      assert.equal(results[0].sourceId, 'good');
      assert.ok(Date.now() - publishedAt >= 50);
      assert.ok(messages.some((message) => message.includes('HTTP 404') && message.includes('正在搜索')));
      assert.match(messages.at(-1), /搜索完成/);
      assert.equal(counts.get('/searchMissing'), 1);
    });

    await test('a missing search pagination page preserves first-page matches', async ({ context, source }) => {
      source.search.url = `${origin}/searchPaged`; source.search.nextPage = '#next';
      const results = await new OnlineBookService(context).search('测试');
      assert.equal(results.length, 1);
      assert.equal(counts.get('/searchMissing'), 1);
    });

    await test('request watchdog settles promises even when platform destroy does not', async ({ context, source }) => {
      scenario.unsettledSearch = true; source.search.url = `${origin}/searchHang`;
      const options = new OnlineSearchOptions(); options.requestTimeoutMillis = 60;
      options.sourceTimeoutMillis = 500; options.totalTimeoutMillis = 1000;
      const start = Date.now();
      await rejected(() => new OnlineBookService(context, options).search('测试'), /网络请求超时/);
      assert.ok(Date.now() - start < 300);
      assert.equal(counts.get('/searchHang'), 1);
    });

    await test('per-source deadline includes all pages and retains already parsed matches', async ({ context, source }) => {
      source.search.url = `${origin}/searchSlowPages`; source.search.nextPage = '#next';
      const options = new OnlineSearchOptions(); options.requestTimeoutMillis = 1000; options.sourceTimeoutMillis = 80;
      const messages = [];
      const start = Date.now();
      const results = await new OnlineBookService(context, options).search('测试', (message) => messages.push(message));
      assert.equal(results.length, 1);
      assert.ok(Date.now() - start < 300);
      assert.match(messages.at(-1), /书源搜索超时/);
    });

    await test('whole-search deadline aborts stuck workers and does not start queued sources', async ({ context, source }) => {
      scenario.unsettledSearch = true;
      const sources = Array.from({ length: 6 }, (_, index) => ({ ...source, id: `hang${index}`,
        name: `无响应${index}`, search: { ...source.search, url: `${origin}/searchHang${index}` } }));
      context.resourceManager.getRawFileContent = async () => new TextEncoder().encode(JSON.stringify(sources));
      const options = new OnlineSearchOptions(); options.requestTimeoutMillis = 1000;
      options.sourceTimeoutMillis = 1000; options.totalTimeoutMillis = 70;
      const start = Date.now();
      await rejected(() => new OnlineBookService(context, options).search('测试'), /搜索超时/);
      assert.ok(Date.now() - start < 300);
      assert.equal(counts.get('/searchHang4'), undefined);
      assert.equal(counts.get('/searchHang5'), undefined);
    });

    await test('search can be cancelled promptly then restarted without callbacks from the old session', async ({ context, source }) => {
      scenario.unsettledSearch = true; source.search.url = `${origin}/searchB`;
      const hanging = { ...source, id: 'hang', search: { ...source.search, url: `${origin}/searchHang` } };
      context.resourceManager.getRawFileContent = async () => new TextEncoder().encode(JSON.stringify([source, hanging]));
      const service = new OnlineBookService(context);
      const token = new OnlineDownloadCancelToken('搜索已取消');
      const outputs = [];
      const action = service.search('测试', undefined, token, (results) => outputs.push(results.length));
      const checked = rejected(() => action, /搜索已取消/);
      await delay(30);
      assert.ok(outputs.some((count) => count > 0));
      const start = Date.now(); token.cancel(); await checked;
      assert.ok(Date.now() - start < 300);
      const oldCallbacks = outputs.length;
      const results = await service.searchSelected('再次搜索', [source.id]);
      assert.equal(results.length, 1);
      assert.equal(outputs.length, oldCallbacks);
    });
    console.log('20 download/search integration checks passed.');
  } finally { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); }
})().catch((error) => { console.error(error); process.exitCode = 1; });
