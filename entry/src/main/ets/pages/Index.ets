import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { ErrorText } from '../data/ErrorText';
import { LibraryStore } from '../data/LibraryStore';
import {
  BookRecord,
  BookmarkRecord,
  ChapterRecord,
  DailyReadingRecord,
  ImportResult,
  LibrarySnapshot,
  NoteRecord,
  OnlineBookResult,
  SyncTombstoneRecord,
  WebDavConfig,
  ReaderSettings
} from '../model/Models';
import { BookImporter } from '../parser/BookImporter';
import { BackupService } from '../data/BackupService';
import { OnlineBookService } from '../data/OnlineBookService';
import { WebDavSyncService } from '../data/WebDavSyncService';

class ReaderTextSegment {
  text: string;
  marked: boolean;
  color: string;

  constructor(text: string, marked: boolean = false, color: string = '#DDAA43') {
    this.text = text;
    this.marked = marked;
    this.color = color;
  }
}

class ReaderTextRange {
  start: number;
  end: number;
  color: string;

  constructor(start: number, end: number, color: string = '#DDAA43') {
    this.start = start;
    this.end = end;
    this.color = color;
  }
}

@Entry
@Component
struct Index {
  @State private page: string = 'shelf';
  @State private snapshot: LibrarySnapshot = new LibrarySnapshot();
  @State private books: Array<BookRecord> = new Array<BookRecord>();
  @State private chapters: Array<ChapterRecord> = new Array<ChapterRecord>();
  @State private currentBookId: string = '';
  @State private chapterIndex: number = 0;
  @State private showCatalog: boolean = false;
  @State private showSettings: boolean = false;
  @State private noteEditorVisible: boolean = false;
  @State private noteParagraphIndex: number = -1;
  @State private editingNoteId: string = '';
  @State private noteDraft: string = '';
  @State private importing: boolean = false;
  @State private mainTab: string = 'shelf';
  @State private searchVisible: boolean = false;
  @State private searchQuery: string = '';
  @State private moreMenuVisible: boolean = false;
  @State private moreMenuProgress: number = 0;
  @State private gridMode: boolean = true;
  @State private sortMode: number = 0;
  @State private pageProgress: number = 1;
  @State private readerProgress: number = 0;
  @State private catalogProgress: number = 0;
  @State private catalogScrimProgress: number = 0;
  @State private settingsProgress: number = 0;
  @State private noteProgress: number = 0;
  @State private readerControlsVisible: boolean = false;
  @State private readerControlsProgress: number = 0;
  @State private readerTextSize: number = 19;
  @State private readerLineHeight: number = 1.65;
  @State private readerThemeMode: number = 0;
  @State private readerPageMargin: number = 22;
  @State private readerReadMode: number = 1;
  @StorageLink('appInForeground') @Watch('onAppForegroundChanged') private appInForeground: boolean = true;
  @StorageLink('onlineDownloadStatus') @Watch('onOnlineDownloadStatusChanged')
  private backgroundDownloadStatus: string = 'idle';
  @State private readerPages: Array<string> = new Array<string>();
  @State private readerCurrentPageText: string = '';
  @State private readerPageParagraphStarts: Array<number> = new Array<number>();
  @State private readerPageTextStarts: Array<number> = new Array<number>();
  @State private readerPageIndex: number = 0;
  @State private readerViewportWidth: number = 360;
  @State private readerViewportHeight: number = 720;
  @State private pageDragActive: boolean = false;
  @State private pageDragAnimating: boolean = false;
  @State private pageDragDx: number = 0;
  @State private pageDragDirection: number = 0;
  @State private pageDragTargetIndex: number = -1;
  @State private pageDragTargetChapter: number = -1;
  @State private pageDragTargetText: string = '';
  @State private utilityPage: string = '';
  @State private utilityProgress: number = 0;
  @State private categoryFilter: string = '全部';
  @State private selectedBookId: string = '';
  @State private bookTitleDraft: string = '';
  @State private bookCategoryDraft: string = '';
  @State private backgroundOpacity: number = 0.32;
  @State private drawerTab: string = 'catalog';
  @State private onlineKeyword: string = '';
  @State private onlineResults: Array<OnlineBookResult> = new Array<OnlineBookResult>();
  @State private onlineBusy: boolean = false;
  @State private onlineStatus: string = '';
  @State private onlineDownloadingUrl: string = '';
  @State private webDavUrl: string = '';
  @State private webDavUsername: string = '';
  @State private webDavPassword: string = '';
  @State private webDavBusy: boolean = false;
  @State private webDavStatus: string = '';
  @State private webDavProgress: number = 0;
  @State private profileNameDraft: string = '';
  @State private readerSelectionStart: number = -1;
  @State private readerSelectionEnd: number = -1;
  @State private readerSelectionParagraphIndex: number = -1;
  @State private readerSelectionMenuVisible: boolean = false;
  @State private readerSelectionColorVisible: boolean = false;
  private catalogAnimationToken: number = 0;
  private pageDragAnimationToken: number = 0;
  private pageTouchTracking: boolean = false;
  private pageTouchMoved: boolean = false;
  private pageTouchStartX: number = 0;
  private pageTouchStartY: number = 0;
  private pageTouchCurrentX: number = 0;
  private pageTouchStartedAt: number = 0;
  private readerSessionStartedAt: number = 0;
  private readerScroller: Scroller = new Scroller();
  private pagedTextControllers: Map<string, TextController> = new Map<string, TextController>();
  private paragraphTextControllers: Map<number, TextController> = new Map<number, TextController>();
  private activeSelectionController: TextController | undefined = undefined;
  private noteSelectionStart: number = -1;
  private noteSelectionEnd: number = -1;
  private noteSelectedText: string = '';

  aboutToAppear(): void {
    this.reloadLibrary();
  }

  private onOnlineDownloadStatusChanged(): void {
    if (this.backgroundDownloadStatus === 'completed') {
      this.reloadLibrary();
    }
  }

  private onAppForegroundChanged(): void {
    if (this.page !== 'reader') {
      return;
    }
    if (this.appInForeground) {
      this.readerSessionStartedAt = Date.now();
      return;
    }
    if (this.readerReadMode === 1) {
      this.updateScrollOffset();
    }
    this.persistProgress();
    this.readerSessionStartedAt = 0;
  }

  onBackPress(): boolean {
    if (this.readerSelectionStart >= 0) {
      this.closeReaderSelection();
      return true;
    }
    if (this.noteEditorVisible) {
      this.closeNoteEditor();
      return true;
    }
    if (this.showSettings) {
      this.closeSettings();
      return true;
    }
    if (this.showCatalog) {
      this.closeCatalog();
      return true;
    }
    if (this.utilityPage.length > 0) {
      this.closeUtility();
      return true;
    }
    if (this.moreMenuVisible) {
      this.toggleMoreMenu();
      return true;
    }
    if (this.pageDragActive || this.pageDragAnimating) {
      this.resetPageDrag();
      return true;
    }
    if (this.page === 'reader') {
      this.closeReader();
      return true;
    }
    if (this.searchVisible) {
      this.searchVisible = false;
      this.searchQuery = '';
      return true;
    }
    if (this.mainTab !== 'shelf') {
      this.switchMainTab('shelf');
      return true;
    }
    return false;
  }

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private reloadLibrary(): void {
    this.snapshot = LibraryStore.load(this.context());
    this.books = this.sortedBooks(this.snapshot.books);
    this.syncReaderSettingsState();
    this.backgroundOpacity = this.snapshot.bookshelfBackgroundOpacity;
    this.gridMode = this.snapshot.bookshelfGridMode;
    this.sortMode = this.snapshot.bookshelfSortMode;
    this.profileNameDraft = this.snapshot.userName;
  }

  private syncReaderSettingsState(): void {
    this.readerTextSize = this.snapshot.settings.textSize;
    this.readerLineHeight = this.snapshot.settings.lineHeight;
    this.readerThemeMode = this.snapshot.settings.themeMode;
    this.readerPageMargin = this.snapshot.settings.pageMargin;
    this.readerReadMode = this.snapshot.settings.readMode === 0 ? 0 : 1;
  }

  private sortedBooks(source: Array<BookRecord>): Array<BookRecord> {
    const copy = source.slice();
    copy.sort((left: BookRecord, right: BookRecord) => {
      if (left.pinnedAt !== right.pinnedAt) {
        return right.pinnedAt - left.pinnedAt;
      }
      if (this.sortMode === 1) {
        return left.title.localeCompare(right.title);
      }
      if (this.sortMode === 2) {
        return this.chapterProgress(right) - this.chapterProgress(left);
      }
      return right.updatedAt - left.updatedAt;
    });
    return copy;
  }

  private bookRenderKey(book: BookRecord): string {
    return `${book.id}:${book.updatedAt}`;
  }

  private visibleBooks(): Array<BookRecord> {
    const keyword = this.searchQuery.trim().toLowerCase();
    let filtered = keyword.length === 0 ? this.snapshot.books : this.snapshot.books.filter((book: BookRecord) =>
      book.title.toLowerCase().indexOf(keyword) >= 0 || book.author.toLowerCase().indexOf(keyword) >= 0 ||
        book.category.toLowerCase().indexOf(keyword) >= 0 || book.description.toLowerCase().indexOf(keyword) >= 0);
    if (this.categoryFilter === '正在阅读') {
      filtered = filtered.filter((book: BookRecord) => book.finishedAt === 0);
    } else if (this.categoryFilter === '已读完') {
      filtered = filtered.filter((book: BookRecord) => book.finishedAt > 0);
    } else if (this.categoryFilter !== '全部') {
      filtered = filtered.filter((book: BookRecord) => book.category === this.categoryFilter);
    }
    return this.sortedBooks(filtered);
  }

  private openUtility(page: string): void {
    this.moreMenuVisible = false;
    this.moreMenuProgress = 0;
    this.utilityPage = page;
    if (page === 'webdav') {
      this.loadWebDavConfig();
    }
    this.utilityProgress = 0;
    animateTo({ duration: 260, curve: Curve.Friction }, () => this.utilityProgress = 1);
  }

  private closeUtility(): void {
    if (this.utilityPage === 'background') {
      this.snapshot.bookshelfBackgroundOpacity = this.backgroundOpacity;
      LibraryStore.save(this.context(), this.snapshot);
    }
    animateTo({ duration: 170, curve: Curve.EaseIn }, () => this.utilityProgress = 0);
    setTimeout((): void => {
      this.utilityPage = '';
    }, 175);
  }

  private openBookActions(book: BookRecord): void {
    this.selectedBookId = book.id;
    this.bookTitleDraft = book.title;
    this.bookCategoryDraft = book.category;
    this.openUtility('book');
  }

  private selectedBook(): BookRecord | undefined {
    return this.snapshot.books.find((book: BookRecord) => book.id === this.selectedBookId);
  }

  private selectedBookPinned(): boolean {
    const book = this.selectedBook();
    return book !== undefined && book.pinnedAt > 0;
  }

  private selectedBookFinished(): boolean {
    const book = this.selectedBook();
    return book !== undefined && book.finishedAt > 0;
  }

  private toggleSelectedBookPin(): void {
    const book = this.selectedBook();
    if (book !== undefined) {
      this.togglePin(book);
    }
    this.closeUtility();
  }

  private toggleSelectedBookFinished(): void {
    const book = this.selectedBook();
    if (book !== undefined) {
      this.toggleFinished(book);
    }
    this.closeUtility();
  }

  private async searchOnline(): Promise<void> {
    const keyword = this.onlineKeyword.trim();
    if (keyword.length === 0) {
      promptAction.showToast({ message: '请输入书名或作者' });
      return;
    }
    this.onlineBusy = true;
    this.onlineResults = new Array<OnlineBookResult>();
    this.onlineStatus = '正在连接在线书源';
    try {
      const service = new OnlineBookService(this.context());
      this.onlineResults = await service.search(keyword, (message: string): void => {
        this.onlineStatus = message;
      });
      this.onlineStatus = this.onlineResults.length === 0 ? '没有找到结果，可稍后重试或更换关键词' :
        `找到 ${this.onlineResults.length} 个结果`;
    } catch (error) {
      this.onlineStatus = `搜索失败：${ErrorText.from(error as BusinessError)}`;
    } finally {
      this.onlineBusy = false;
    }
  }

  private async downloadOnline(result: OnlineBookResult): Promise<void> {
    if (this.onlineDownloadingUrl.length > 0) {
      return;
    }
    this.onlineDownloadingUrl = result.url;
    this.onlineStatus = `准备下载《${result.bookName}》`;
    try {
      const service = new OnlineBookService(this.context());
      const book = await service.downloadToLibrary(result, 'txt', (message: string): void => {
        this.onlineStatus = message;
      });
      this.reloadLibrary();
      this.onlineStatus = `《${book.title}》已下载到书架`;
      promptAction.showToast({ message: '下载完成，书架已更新' });
    } catch (error) {
      this.onlineStatus = `下载失败：${ErrorText.from(error as BusinessError)}`;
    } finally {
      this.onlineDownloadingUrl = '';
    }
  }

  private loadWebDavConfig(): void {
    const config = new WebDavSyncService(this.context()).loadConfig();
    this.webDavUrl = config.url;
    this.webDavUsername = config.username;
    this.webDavPassword = config.password;
    this.webDavStatus = config.lastStatus;
    this.webDavProgress = config.lastSyncAt > 0 && config.lastStatus === '同步完成' ? 100 : 0;
  }

  private webDavConfig(): WebDavConfig {
    const config = new WebDavConfig();
    config.url = this.webDavUrl.trim();
    config.username = this.webDavUsername.trim();
    config.password = this.webDavPassword;
    config.enabled = config.url.length > 0;
    const saved = new WebDavSyncService(this.context()).loadConfig();
    config.lastSyncAt = saved.lastSyncAt;
    config.lastStatus = saved.lastStatus;
    return config;
  }

  private saveWebDav(): void {
    try {
      const service = new WebDavSyncService(this.context());
      service.saveConfig(this.webDavConfig());
      this.webDavStatus = '配置已保存';
      promptAction.showToast({ message: 'WebDAV 配置已保存' });
    } catch (error) {
      this.webDavStatus = `保存失败：${ErrorText.from(error as BusinessError)}`;
    }
  }

  private async testWebDav(): Promise<void> {
    if (this.webDavBusy) {
      return;
    }
    this.webDavBusy = true;
    this.webDavStatus = '正在测试连接';
    try {
      const service = new WebDavSyncService(this.context());
      const config = this.webDavConfig();
      await service.test(config);
      config.lastStatus = '连接成功';
      service.saveConfig(config);
      this.webDavStatus = '连接成功';
    } catch (error) {
      this.webDavStatus = `连接失败：${ErrorText.from(error as BusinessError)}`;
      try {
        const config = this.webDavConfig();
        config.lastStatus = this.webDavStatus;
        new WebDavSyncService(this.context()).saveConfig(config);
      } catch (saveError) {
        // Keep the actionable connection error visible even if persisting the status fails.
      }
    } finally {
      this.webDavBusy = false;
    }
  }

  private async syncWebDav(): Promise<void> {
    if (this.webDavBusy) {
      return;
    }
    this.webDavBusy = true;
    this.webDavProgress = 0;
    try {
      const service = new WebDavSyncService(this.context());
      const config = this.webDavConfig();
      service.saveConfig(config);
      this.snapshot = await service.sync(config, (message: string, percent: number): void => {
        this.webDavStatus = message;
        this.webDavProgress = percent;
      });
      this.reloadLibrary();
      promptAction.showToast({ message: 'WebDAV 同步完成' });
    } catch (error) {
      this.webDavStatus = `同步失败：${ErrorText.from(error as BusinessError)}`;
      try {
        const config = this.webDavConfig();
        config.lastStatus = this.webDavStatus;
        new WebDavSyncService(this.context()).saveConfig(config);
      } catch (saveError) {
        // Keep the actionable sync error visible even if persisting the status fails.
      }
    } finally {
      this.webDavBusy = false;
    }
  }

  private saveProfile(): void {
    const name = this.profileNameDraft.trim();
    if (name.length === 0 || name.length > 12) {
      promptAction.showToast({ message: '昵称长度应为 1 到 12 个字符' });
      return;
    }
    this.snapshot.userName = name;
    this.snapshot.profileUpdatedAt = Date.now();
    LibraryStore.save(this.context(), this.snapshot);
    this.closeUtility();
  }

  private confirmClearReadingStats(): void {
    AlertDialog.show({
      title: '清除阅读统计',
      message: '将清除累计阅读时长和连续阅读记录，书籍进度不会改变。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '清除',
        fontColor: '#B74434',
        action: () => {
          this.snapshot.dailyReading.forEach((daily: DailyReadingRecord): void => {
            this.recordSyncDeletion('reading', daily.syncId);
          });
          this.snapshot.dailyReading = new Array<DailyReadingRecord>();
          LibraryStore.save(this.context(), this.snapshot);
          this.snapshot = LibraryStore.load(this.context());
        }
      }
    });
  }

  private switchMainTab(tab: string): void {
    if (tab === this.mainTab) {
      return;
    }
    animateTo({ duration: 120, curve: Curve.EaseIn }, () => {
      this.pageProgress = 0;
    });
    setTimeout(() => {
      this.mainTab = tab;
      animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
        this.pageProgress = 1;
      });
    }, 125);
  }

  private toggleMoreMenu(): void {
    if (this.moreMenuVisible) {
      animateTo({ duration: 150, curve: Curve.EaseIn }, () => this.moreMenuProgress = 0);
      setTimeout((): void => {
        this.moreMenuVisible = false;
      }, 155);
    } else {
      this.moreMenuVisible = true;
      this.moreMenuProgress = 0;
      animateTo({ duration: 240, curve: Curve.Friction }, () => this.moreMenuProgress = 1);
    }
  }

  private cycleSortMode(): void {
    this.sortMode = (this.sortMode + 1) % 3;
    this.snapshot.bookshelfSortMode = this.sortMode;
    LibraryStore.save(this.context(), this.snapshot);
    this.books = this.visibleBooks();
    promptAction.showToast({ message: this.sortMode === 0 ? '按最近阅读排序' :
      (this.sortMode === 1 ? '按书名排序' : '按阅读进度排序') });
    this.toggleMoreMenu();
  }

  private openOnlineSearch(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/OnlineSearch' });
  }

  private openBrowser(): void {
    this.moreMenuVisible = false;
    this.moreMenuProgress = 0;
    this.getUIContext().getRouter().pushUrl({ url: 'pages/Browser' });
  }

  private toggleGridMode(): void {
    this.gridMode = !this.gridMode;
    this.snapshot.bookshelfGridMode = this.gridMode;
    LibraryStore.save(this.context(), this.snapshot);
    this.toggleMoreMenu();
  }

  private openCatalog(): void {
    const animationToken = ++this.catalogAnimationToken;
    this.showCatalog = true;
    this.catalogProgress = 0;
    this.catalogScrimProgress = 0;
    animateTo({ duration: 260, curve: Curve.Friction }, () => this.catalogProgress = 1);
    setTimeout(() => {
      if (animationToken !== this.catalogAnimationToken || !this.showCatalog) {
        return;
      }
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => this.catalogScrimProgress = 1);
    }, 190);
  }

  private currentBookmarks(): Array<BookmarkRecord> {
    return this.snapshot.bookmarks.filter((item: BookmarkRecord) => item.bookId === this.currentBookId);
  }

  private currentNotes(): Array<NoteRecord> {
    return this.snapshot.notes.filter((item: NoteRecord) => item.bookId === this.currentBookId &&
      item.noteText.trim().length > 0);
  }

  private openBookmark(bookmark: BookmarkRecord): void {
    this.chapterIndex = Math.max(0, Math.min(bookmark.chapterIndex, this.chapters.length - 1));
    this.readerPageIndex = Math.max(0, bookmark.pageIndex);
    this.rebuildReaderPages(this.readerPageIndex);
    const book = this.currentBook();
    if (book !== undefined) {
      book.currentChapterIndex = this.chapterIndex;
      book.currentPageIndex = this.readerPageIndex;
      book.scrollOffset = bookmark.scrollOffset;
    }
    this.closeCatalog();
    if (this.readerReadMode === 1) {
      setTimeout((): void => {
        this.readerScroller.scrollTo({ xOffset: 0, yOffset: bookmark.scrollOffset });
      }, 280);
    }
    this.persistProgress();
  }

  private openDrawerNote(note: NoteRecord): void {
    this.chapterIndex = Math.max(0, Math.min(note.chapterIndex, this.chapters.length - 1));
    const paragraphs = this.paragraphs();
    const paragraphIndex = Math.max(0, Math.min(note.paragraphIndex, paragraphs.length - 1));
    this.rebuildReaderPages(0);
    const absoluteOffset = note.textStartOffset >= 0 ? note.textStartOffset :
      this.paragraphAbsoluteStart(paragraphIndex);
    this.readerPageIndex = this.pageIndexForAbsoluteOffset(absoluteOffset);
    this.rebuildReaderPages(this.readerPageIndex);
    const scrollOffset = this.estimatedParagraphScrollOffset(paragraphIndex);
    const book = this.currentBook();
    if (book !== undefined) {
      book.currentChapterIndex = this.chapterIndex;
      book.currentPageIndex = this.readerPageIndex;
      book.scrollOffset = scrollOffset;
    }
    this.closeCatalog();
    setTimeout((): void => {
      if (this.readerReadMode === 1) {
        this.readerScroller.scrollTo({ xOffset: 0, yOffset: scrollOffset });
      }
      this.openNoteEditor(paragraphIndex, note);
    }, 280);
    this.persistProgress();
  }

  private closeCatalog(): void {
    this.catalogAnimationToken++;
    animateTo({ duration: 120, curve: Curve.EaseIn }, () => this.catalogScrimProgress = 0);
    setTimeout(() => {
      animateTo({ duration: 190, curve: Curve.EaseIn }, () => this.catalogProgress = 0);
    }, 70);
    setTimeout((): void => {
      this.showCatalog = false;
    }, 265);
  }

  private openSettings(): void {
    this.showSettings = true;
    this.settingsProgress = 0;
    animateTo({ duration: 300, curve: Curve.Friction }, () => this.settingsProgress = 1);
  }

  private closeSettings(): void {
    this.saveSettings();
    animateTo({ duration: 190, curve: Curve.EaseIn }, () => this.settingsProgress = 0);
    setTimeout((): void => {
      this.showSettings = false;
    }, 195);
  }

  private setReaderReadMode(mode: number): void {
    const normalizedMode = mode === 0 ? 0 : 1;
    if (this.readerReadMode === normalizedMode) {
      return;
    }
    this.closeReaderSelection();
    this.resetPageDrag();
    this.readerReadMode = normalizedMode;
    const book = this.currentBook();
    if (normalizedMode === 0) {
      const targetPage = book === undefined ? 0 : book.currentPageIndex;
      this.rebuildReaderPages(targetPage);
      return;
    }
    const targetOffset = book === undefined ? 0 : book.scrollOffset;
    setTimeout((): void => {
      if (this.readerReadMode === 1) {
        this.readerScroller.scrollTo({ xOffset: 0, yOffset: targetOffset });
      }
    }, 40);
  }

  private toggleReaderControls(): void {
    if (this.showCatalog || this.showSettings || this.noteEditorVisible) {
      return;
    }
    this.readerControlsVisible = !this.readerControlsVisible;
    animateTo({ duration: this.readerControlsVisible ? 220 : 160,
      curve: this.readerControlsVisible ? Curve.EaseOut : Curve.EaseIn }, () => {
      this.readerControlsProgress = this.readerControlsVisible ? 1 : 0;
    });
  }

  private async importBooks(): Promise<void> {
    if (this.importing) {
      return;
    }
    this.importing = true;
    try {
      const result: ImportResult = await BookImporter.selectAndImport(this.context());
      this.reloadLibrary();
      if (result.books.length > 0) {
        promptAction.showToast({ message: `已导入 ${result.books.length} 本书` });
      }
      if (result.updatedCount > 0) {
        promptAction.showToast({ message: `已更新 ${result.updatedCount} 本重复书籍` });
      }
      if (result.errors.length > 0) {
        promptAction.showToast({ message: result.errors[0] });
      }
    } catch (error) {
      const message = ErrorText.from(error as BusinessError);
      if (message.indexOf('cancel') < 0 && message.indexOf('Cancel') < 0) {
        promptAction.showToast({ message: `导入失败：${message}` });
      }
    } finally {
      this.importing = false;
    }
  }

  private openBook(book: BookRecord): void {
    const loaded = LibraryStore.loadChapters(book);
    if (loaded.length === 0) {
      promptAction.showToast({ message: '没有可读取的章节' });
      return;
    }
    this.pagedTextControllers.clear();
    this.paragraphTextControllers.clear();
    this.currentBookId = book.id;
    this.chapters = loaded;
    this.chapterIndex = Math.max(0, Math.min(book.currentChapterIndex, loaded.length - 1));
    this.readerPageIndex = book.currentPageIndex === undefined ? 0 : book.currentPageIndex;
    this.rebuildReaderPages(this.readerPageIndex);
    this.page = 'reader';
    this.readerProgress = 0;
    this.showCatalog = false;
    this.showSettings = false;
    this.readerControlsVisible = false;
    this.readerControlsProgress = 0;
    this.closeReaderSelection();
    this.readerSessionStartedAt = Date.now();
    setTimeout(() => {
      animateTo({ duration: 320, curve: Curve.EaseOut }, () => this.readerProgress = 1);
    }, 20);
    const offset = book.scrollOffset;
    setTimeout(() => {
      this.readerScroller.scrollTo({ xOffset: 0, yOffset: offset });
    }, 80);
  }

  private currentBook(): BookRecord | undefined {
    return this.snapshot.books.find((book: BookRecord) => book.id === this.currentBookId);
  }

  private currentBookTitle(): string {
    const book = this.currentBook();
    return book === undefined ? '' : book.title;
  }

  private currentChapter(): ChapterRecord {
    if (this.chapterIndex >= 0 && this.chapterIndex < this.chapters.length) {
      return this.chapters[this.chapterIndex];
    }
    return new ChapterRecord('', '');
  }

  private paragraphs(): Array<string> {
    return this.paragraphsForChapter(this.chapterIndex);
  }

  private paragraphsForChapter(index: number): Array<string> {
    if (index < 0 || index >= this.chapters.length) {
      return ['本章暂无正文'];
    }
    const content = this.chapters[index].content.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const raw = content.split(/\n+/g);
    const result = new Array<string>();
    raw.forEach((paragraph: string) => {
      const value = paragraph.trim();
      if (value.length > 0) {
        result.push(value);
      }
    });
    if (result.length === 0) {
      result.push('本章暂无正文');
    }
    return result;
  }

  private readerSafeTop(): number {
    // Reserve a full text line plus a fixed guard for centered/pill-shaped camera cutouts.
    return Math.max(56, Math.round(this.readerTextSize * this.readerLineHeight + this.readerPageMargin + 12));
  }

  private isReaderLandscape(): boolean {
    return this.readerViewportWidth > this.readerViewportHeight;
  }

  private readerHorizontalPadding(): number {
    const centeredPadding = Math.max(0, (this.readerViewportWidth - 760) / 2);
    return Math.max(this.readerPageMargin, centeredPadding);
  }

  private readerSettingsPanelHeight(): number {
    const viewportHeight = Math.max(1, this.readerViewportHeight);
    if (this.isReaderLandscape()) {
      return Math.min(360, Math.max(240, viewportHeight - 24));
    }
    return Math.min(390, Math.max(300, viewportHeight * 0.38));
  }

  private readerSettingsPanelTop(): number {
    return Math.max(0, this.readerViewportHeight - this.readerSettingsPanelHeight());
  }

  private estimatedCharactersPerLine(): number {
    const usableWidth = Math.max(180, this.readerViewportWidth - this.readerHorizontalPadding() * 2);
    return Math.max(8, Math.floor(usableWidth / (this.readerTextSize * 1.08)));
  }

  private estimatedPageCapacity(): number {
    const charactersPerLine = this.estimatedCharactersPerLine();
    const usableHeight = Math.max(240, this.readerViewportHeight - this.readerSafeTop() - 66);
    // Keep two full lines unused: one for custom-font metrics and one to lift the last line clear of the bottom edge.
    const lines = Math.max(6, Math.floor(usableHeight / (this.readerTextSize * this.readerLineHeight)) - 2);
    return Math.max(80, charactersPerLine * lines);
  }

  private createPages(chapterIndex: number, captureStarts: boolean): Array<string> {
    const result = new Array<string>();
    const starts = new Array<number>();
    const textStarts = new Array<number>();
    if (chapterIndex < 0 || chapterIndex >= this.chapters.length) {
      result.push('本章暂无正文');
      starts.push(0);
      textStarts.push(0);
      if (captureStarts) {
        this.readerPageParagraphStarts = starts;
        this.readerPageTextStarts = textStarts;
      }
      return result;
    }
    const capacity = this.estimatedPageCapacity();
    const charactersPerLine = this.estimatedCharactersPerLine();
    const paragraphs = this.paragraphsForChapter(chapterIndex);
    let current = this.chapters[chapterIndex].title;
    // The centered title and its lower margin occupy roughly two text lines on the first page.
    let currentCost = current.length + charactersPerLine * 2;
    let currentStart = 0;
    let currentTextStart = 0;
    let canonicalCursor = current.length;
    for (let paragraphIndex = 0; paragraphIndex < paragraphs.length; paragraphIndex++) {
      let remaining = `　　${paragraphs[paragraphIndex]}`;
      canonicalCursor += 2;
      let remainingTextStart = canonicalCursor;
      canonicalCursor += remaining.length;
      while (remaining.length > 0) {
        const separator = current.length > 0 ? '\n\n' : '';
        // Two newline characters create one visible blank line between paragraphs.
        const separatorCost = current.length > 0 ? charactersPerLine : 0;
        const room = capacity - currentCost - separatorCost;
        if (room <= 0) {
          result.push(current);
          starts.push(currentStart);
          textStarts.push(currentTextStart);
          current = '';
          currentCost = 0;
          currentStart = paragraphIndex;
          currentTextStart = remainingTextStart;
          continue;
        }
        if (remaining.length <= room) {
          current += separator + remaining;
          currentCost += separatorCost + remaining.length;
          remaining = '';
        } else {
          current += separator + remaining.substring(0, room);
          remaining = remaining.substring(room);
          result.push(current);
          starts.push(currentStart);
          textStarts.push(currentTextStart);
          remainingTextStart += room;
          currentTextStart = remainingTextStart;
          current = '';
          currentCost = 0;
          currentStart = paragraphIndex;
        }
      }
    }
    if (current.length > 0 || result.length === 0) {
      result.push(current.length > 0 ? current : '本章暂无正文');
      starts.push(currentStart);
      textStarts.push(currentTextStart);
    }
    if (captureStarts) {
      this.readerPageParagraphStarts = starts;
      this.readerPageTextStarts = textStarts;
    }
    return result;
  }

  private rebuildReaderPages(targetIndex: number = -1): void {
    const pages = this.createPages(this.chapterIndex, true);
    this.readerPages = pages;
    const requested = targetIndex >= 0 ? targetIndex : this.readerPageIndex;
    this.readerPageIndex = Math.max(0, Math.min(requested, pages.length - 1));
    this.readerCurrentPageText = pages[this.readerPageIndex];
    const book = this.currentBook();
    if (book !== undefined) {
      book.currentPageIndex = this.readerPageIndex;
    }
  }

  private currentPagedText(): string {
    return this.readerPageIndex >= 0 && this.readerPageIndex < this.readerPages.length ?
      this.readerPages[this.readerPageIndex] : '';
  }

  private pagedNoteParagraphIndex(): number {
    return this.readerPageIndex >= 0 && this.readerPageIndex < this.readerPageParagraphStarts.length ?
      this.readerPageParagraphStarts[this.readerPageIndex] : 0;
  }

  private paragraphTextController(index: number): TextController {
    const existing = this.paragraphTextControllers.get(index);
    if (existing !== undefined) {
      return existing;
    }
    const controller = new TextController();
    this.paragraphTextControllers.set(index, controller);
    return controller;
  }

  private currentPagedTextController(): TextController {
    const key = `${this.chapterIndex}_${this.readerPageIndex}`;
    const existing = this.pagedTextControllers.get(key);
    if (existing !== undefined) {
      return existing;
    }
    const controller = new TextController();
    this.pagedTextControllers.set(key, controller);
    return controller;
  }

  private displayTextForChapter(index: number): string {
    if (index < 0 || index >= this.chapters.length) {
      return '本章暂无正文';
    }
    let displayText = this.chapters[index].title;
    this.paragraphsForChapter(index).forEach((paragraph: string): void => {
      displayText += `\n\n　　${paragraph}`;
    });
    return displayText;
  }

  private paragraphAbsoluteStart(paragraphIndex: number, requestedChapterIndex: number = -1): number {
    const chapterIndex = requestedChapterIndex < 0 ? this.chapterIndex : requestedChapterIndex;
    const paragraphs = this.paragraphsForChapter(chapterIndex);
    if (paragraphIndex < 0 || paragraphIndex >= paragraphs.length) {
      return 0;
    }
    const displayText = this.displayTextForChapter(chapterIndex);
    let cursor = chapterIndex >= 0 && chapterIndex < this.chapters.length ? this.chapters[chapterIndex].title.length : 0;
    for (let index = 0; index <= paragraphIndex; index++) {
      const displayedParagraph = `　　${paragraphs[index]}`;
      const found = displayText.indexOf(displayedParagraph, cursor);
      if (index === paragraphIndex) {
        return found >= 0 ? found : cursor;
      }
      if (found >= 0) {
        cursor = found + displayedParagraph.length;
      }
    }
    return cursor;
  }

  private paragraphForAbsoluteOffset(offset: number): number {
    const paragraphs = this.paragraphs();
    for (let index = 0; index < paragraphs.length; index++) {
      const start = this.paragraphAbsoluteStart(index);
      const end = start + 2 + paragraphs[index].length;
      if (offset >= start && offset <= end) {
        return index;
      }
    }
    return this.pagedNoteParagraphIndex();
  }

  private currentPageAbsoluteStart(): number {
    return this.readerPageIndex >= 0 && this.readerPageIndex < this.readerPageTextStarts.length ?
      this.readerPageTextStarts[this.readerPageIndex] : 0;
  }

  private pageIndexForAbsoluteOffset(offset: number): number {
    for (let index = this.readerPageTextStarts.length - 1; index >= 0; index--) {
      if (offset >= this.readerPageTextStarts[index]) {
        return index;
      }
    }
    return 0;
  }

  private estimatedParagraphScrollOffset(paragraphIndex: number): number {
    const paragraphs = this.paragraphs();
    const safeIndex = Math.max(0, Math.min(paragraphIndex, paragraphs.length - 1));
    const charactersPerLine = this.estimatedCharactersPerLine();
    const lineHeight = this.readerTextSize * this.readerLineHeight;
    let offset = this.readerSafeTop() + (this.readerTextSize + 5) * this.readerLineHeight + 32;
    for (let index = 0; index < safeIndex; index++) {
      offset += Math.max(1, Math.ceil((paragraphs[index].length + 2) / charactersPerLine)) * lineHeight + 15;
    }
    return Math.max(0, offset);
  }

  private updateReaderSelection(text: string, absoluteStart: number, controller: TextController,
    selectionStart: number, selectionEnd: number): void {
    if (selectionStart < 0 || selectionEnd <= selectionStart || selectionStart >= text.length) {
      return;
    }
    const safeEnd = Math.min(text.length, selectionEnd);
    this.readerSelectionStart = absoluteStart + selectionStart;
    this.readerSelectionEnd = absoluteStart + safeEnd;
    this.readerSelectionParagraphIndex = this.paragraphForAbsoluteOffset(this.readerSelectionStart);
    this.activeSelectionController = controller;
  }

  private noteTextRange(note: NoteRecord): ReaderTextRange | undefined {
    if (note.textStartOffset >= 0 && note.textEndOffset > note.textStartOffset) {
      return new ReaderTextRange(note.textStartOffset, note.textEndOffset, note.color);
    }
    if (note.paragraphIndex < 0 || note.paragraphIndex >= this.paragraphsForChapter(note.chapterIndex).length ||
      note.selectedText.length === 0) {
      return undefined;
    }
    const paragraph = `　　${this.paragraphsForChapter(note.chapterIndex)[note.paragraphIndex]}`;
    const localStart = paragraph.indexOf(note.selectedText);
    if (localStart < 0) {
      return undefined;
    }
    const start = this.paragraphAbsoluteStart(note.paragraphIndex, note.chapterIndex) + localStart;
    return new ReaderTextRange(start, start + note.selectedText.length, note.color);
  }

  private markRanges(chapterIndex: number): Array<ReaderTextRange> {
    const ranges = new Array<ReaderTextRange>();
    this.snapshot.notes.forEach((note: NoteRecord): void => {
      if (note.bookId !== this.currentBookId || note.chapterIndex !== chapterIndex || note.noteText.trim().length > 0) {
        return;
      }
      const range = this.noteTextRange(note);
      if (range !== undefined) {
        ranges.push(range);
      }
    });
    return ranges;
  }

  private readerTextSegments(text: string, absoluteStart: number, chapterIndex: number): Array<ReaderTextSegment> {
    const result = new Array<ReaderTextSegment>();
    if (text.length === 0) {
      return result;
    }
    const absoluteEnd = absoluteStart + text.length;
    const ranges = this.markRanges(chapterIndex).filter((range: ReaderTextRange): boolean =>
      range.end > absoluteStart && range.start < absoluteEnd);
    if (ranges.length === 0) {
      result.push(new ReaderTextSegment(text));
      return result;
    }
    const boundaries = new Array<number>();
    boundaries.push(0);
    boundaries.push(text.length);
    ranges.forEach((range: ReaderTextRange): void => {
      boundaries.push(Math.max(0, range.start - absoluteStart));
      boundaries.push(Math.min(text.length, range.end - absoluteStart));
    });
    boundaries.sort((left: number, right: number): number => left - right);
    let previous = -1;
    const uniqueBoundaries = new Array<number>();
    boundaries.forEach((value: number): void => {
      if (value !== previous) {
        uniqueBoundaries.push(value);
        previous = value;
      }
    });
    let segmentIndex = 0;
    while (segmentIndex < uniqueBoundaries.length - 1) {
      const localStart = uniqueBoundaries[segmentIndex];
      const localEnd = uniqueBoundaries[segmentIndex + 1];
      if (localEnd <= localStart) {
        segmentIndex++;
        continue;
      }
      const absoluteMid = absoluteStart + localStart;
      const active = ranges.find((range: ReaderTextRange): boolean =>
        absoluteMid >= range.start && absoluteMid < range.end);
      result.push(new ReaderTextSegment(text.substring(localStart, localEnd), active !== undefined,
        active === undefined ? '#DDAA43' : active.color));
      segmentIndex++;
    }
    return result;
  }

  private readerSelectionHasMark(): boolean {
    if (this.readerSelectionStart < 0 || this.readerSelectionEnd <= this.readerSelectionStart) {
      return false;
    }
    return this.markRanges(this.chapterIndex).some((range: ReaderTextRange): boolean =>
      range.end > this.readerSelectionStart && range.start < this.readerSelectionEnd);
  }

  private selectedReaderText(): string {
    const displayText = this.displayTextForChapter(this.chapterIndex);
    const start = Math.max(0, Math.min(displayText.length, this.readerSelectionStart));
    const end = Math.max(start, Math.min(displayText.length, this.readerSelectionEnd));
    return displayText.substring(start, end);
  }

  private showReaderSelectionMenu(): void {
    this.readerSelectionMenuVisible = true;
    this.readerSelectionColorVisible = false;
    if (this.readerControlsVisible) {
      this.readerControlsVisible = false;
      animateTo({ duration: 150, curve: Curve.EaseIn }, (): void => {
        this.readerControlsProgress = 0;
      });
    }
  }

  private hideReaderSelectionMenu(): void {
    this.readerSelectionMenuVisible = false;
    this.readerSelectionColorVisible = false;
  }

  private closeReaderSelection(): void {
    if (this.activeSelectionController !== undefined) {
      this.activeSelectionController.closeSelectionMenu();
    }
    this.readerSelectionStart = -1;
    this.readerSelectionEnd = -1;
    this.readerSelectionParagraphIndex = -1;
    this.readerSelectionMenuVisible = false;
    this.readerSelectionColorVisible = false;
    this.activeSelectionController = undefined;
  }

  private saveReaderMark(color: string): void {
    const selectedText = this.selectedReaderText().trim();
    if (this.readerSelectionStart < 0 || this.readerSelectionEnd <= this.readerSelectionStart ||
      selectedText.length === 0) {
      return;
    }
    const note = new NoteRecord();
    note.id = `${Date.now()}_mark`;
    note.bookId = this.currentBookId;
    note.chapterIndex = this.chapterIndex;
    note.paragraphIndex = this.readerSelectionParagraphIndex;
    note.selectedText = selectedText;
    note.noteText = '';
    note.color = color;
    note.textStartOffset = this.readerSelectionStart;
    note.textEndOffset = this.readerSelectionEnd;
    note.createdAt = Date.now();
    note.updatedAt = note.createdAt;
    this.snapshot.notes.push(note);
    LibraryStore.save(this.context(), this.snapshot);
    this.snapshot = LibraryStore.load(this.context());
    this.closeReaderSelection();
    promptAction.showToast({ message: '已添加标记' });
  }

  private deleteReaderMarks(): void {
    const removed = this.snapshot.notes.filter((note: NoteRecord): boolean => {
      if (note.bookId !== this.currentBookId || note.chapterIndex !== this.chapterIndex ||
        note.noteText.trim().length > 0) return false;
      const range = this.noteTextRange(note);
      return range !== undefined && range.end > this.readerSelectionStart && range.start < this.readerSelectionEnd;
    });
    removed.forEach((note: NoteRecord): void => this.recordSyncDeletion('note', note.syncId));
    this.snapshot.notes = this.snapshot.notes.filter((note: NoteRecord): boolean => {
      if (note.bookId !== this.currentBookId || note.chapterIndex !== this.chapterIndex ||
        note.noteText.trim().length > 0) {
        return true;
      }
      const range = this.noteTextRange(note);
      return range === undefined || range.end <= this.readerSelectionStart || range.start >= this.readerSelectionEnd;
    });
    LibraryStore.save(this.context(), this.snapshot);
    this.snapshot = LibraryStore.load(this.context());
    this.closeReaderSelection();
    promptAction.showToast({ message: '已删除标记' });
  }

  private async copyReaderSelection(): Promise<void> {
    const text = this.selectedReaderText();
    if (text.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      promptAction.showToast({ message: '已复制选中文本' });
    } catch (error) {
      promptAction.showToast({ message: `复制失败：${ErrorText.from(error as BusinessError)}` });
    }
    this.closeReaderSelection();
  }

  private commentReaderSelection(): void {
    const paragraphIndex = this.readerSelectionParagraphIndex;
    const selectionStart = this.readerSelectionStart;
    const selectionEnd = this.readerSelectionEnd;
    const selectedText = this.selectedReaderText().trim();
    this.closeReaderSelection();
    const paragraphs = this.paragraphs();
    if (paragraphIndex >= 0 && paragraphIndex < paragraphs.length) {
      this.openNoteEditor(paragraphIndex, undefined, selectionStart, selectionEnd,
        selectedText.length > 0 ? selectedText : paragraphs[paragraphIndex]);
    }
  }

  private preparePageTarget(direction: number): boolean {
    let targetChapter = this.chapterIndex;
    let targetIndex = this.readerPageIndex + (direction < 0 ? 1 : -1);
    let targetPages = this.readerPages;
    if (targetIndex >= targetPages.length && direction < 0) {
      targetChapter++;
      if (targetChapter >= this.chapters.length) {
        return false;
      }
      targetPages = this.createPages(targetChapter, false);
      targetIndex = 0;
    } else if (targetIndex < 0 && direction > 0) {
      targetChapter--;
      if (targetChapter < 0) {
        return false;
      }
      targetPages = this.createPages(targetChapter, false);
      targetIndex = targetPages.length - 1;
    }
    if (targetIndex < 0 || targetIndex >= targetPages.length) {
      return false;
    }
    this.pageDragActive = true;
    this.pageDragDirection = direction;
    this.pageDragTargetChapter = targetChapter;
    this.pageDragTargetIndex = targetIndex;
    this.pageDragTargetText = targetPages[targetIndex];
    if (this.readerControlsVisible) {
      this.readerControlsVisible = false;
      animateTo({ duration: 150, curve: Curve.EaseIn }, () => this.readerControlsProgress = 0);
    }
    return true;
  }

  private turnPageByTap(direction: number): void {
    if (this.pageDragActive || this.pageDragAnimating || !this.preparePageTarget(direction)) {
      return;
    }
    const width = Math.max(1, this.readerViewportWidth);
    this.pageDragDx = 0;
    this.pageDragAnimating = true;
    const animationToken = ++this.pageDragAnimationToken;
    animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
      this.pageDragDx = direction < 0 ? -width : width;
    });
    setTimeout((): void => {
      if (animationToken === this.pageDragAnimationToken) {
        this.commitPageDrag();
      }
    }, 285);
  }

  private handlePagedTap(localX: number): void {
    if (this.pageDragActive || this.pageDragAnimating) {
      return;
    }
    const width = Math.max(1, this.readerViewportWidth);
    if (localX < width / 3) {
      this.turnPageByTap(1);
    } else if (localX > width * 2 / 3) {
      this.turnPageByTap(-1);
    } else {
      this.toggleReaderControls();
    }
  }

  private updatePageDrag(dx: number): void {
    if (this.pageDragAnimating || this.readerReadMode !== 0) {
      return;
    }
    if (!this.pageDragActive) {
      if (Math.abs(dx) < 20) {
        return;
      }
      if (!this.preparePageTarget(dx < 0 ? -1 : 1)) {
        return;
      }
    }
    const width = Math.max(1, this.readerViewportWidth);
    this.pageDragDx = this.pageDragDirection < 0 ? Math.max(-width, Math.min(0, dx)) :
      Math.min(width, Math.max(0, dx));
  }

  private pageTouchX(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].x;
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].x;
    }
    return this.pageTouchCurrentX;
  }

  private pageTouchY(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].y;
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].y;
    }
    return this.pageTouchStartY;
  }

  private handlePagedTouch(event: TouchEvent): void {
    const x = this.pageTouchX(event);
    const y = this.pageTouchY(event);
    if (event.type === TouchType.Down) {
      if (this.pageDragAnimating) {
        return;
      }
      this.pageTouchTracking = true;
      this.pageTouchMoved = false;
      this.pageTouchStartX = x;
      this.pageTouchStartY = y;
      this.pageTouchCurrentX = x;
      this.pageTouchStartedAt = Date.now();
      return;
    }
    if (!this.pageTouchTracking) {
      return;
    }
    this.pageTouchCurrentX = x;
    if (event.type === TouchType.Move) {
      const dx = x - this.pageTouchStartX;
      const dy = y - this.pageTouchStartY;
      if (!this.pageTouchMoved) {
        if (Math.abs(dx) < 20) {
          return;
        }
        if (Math.abs(dx) <= Math.abs(dy)) {
          this.pageTouchTracking = false;
          return;
        }
        this.pageTouchMoved = true;
      }
      this.updatePageDrag(dx);
      return;
    }
    if (event.type === TouchType.Up) {
      const heldFor = Date.now() - this.pageTouchStartedAt;
      const moved = this.pageTouchMoved;
      this.pageTouchTracking = false;
      this.pageTouchMoved = false;
      if (this.pageDragActive) {
        this.finishPageDrag(true);
        return;
      }
      if (!moved && heldFor < 450) {
        this.handlePagedTap(x);
      }
      return;
    }
    if (event.type === TouchType.Cancel) {
      this.pageTouchTracking = false;
      this.pageTouchMoved = false;
      this.finishPageDrag(false);
    }
  }

  private finishPageDrag(canComplete: boolean): void {
    if (!this.pageDragActive || this.pageDragAnimating) {
      return;
    }
    const width = Math.max(1, this.readerViewportWidth);
    const complete = canComplete && Math.abs(this.pageDragDx) >= width / 10;
    this.pageDragAnimating = true;
    const animationToken = ++this.pageDragAnimationToken;
    if (complete) {
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.pageDragDx = this.pageDragDirection < 0 ? -width : width;
      });
      setTimeout((): void => {
        if (animationToken === this.pageDragAnimationToken) {
          this.commitPageDrag();
        }
      }, 185);
    } else {
      animateTo({ duration: 160, curve: Curve.EaseOut }, () => this.pageDragDx = 0);
      setTimeout((): void => {
        if (animationToken === this.pageDragAnimationToken) {
          this.resetPageDrag();
        }
      }, 165);
    }
  }

  private commitPageDrag(): void {
    const targetChapter = this.pageDragTargetChapter;
    const targetIndex = this.pageDragTargetIndex;
    this.chapterIndex = targetChapter;
    this.readerPageIndex = targetIndex;
    this.rebuildReaderPages(targetIndex);
    const book = this.currentBook();
    if (book !== undefined) {
      book.currentChapterIndex = this.chapterIndex;
      book.currentPageIndex = this.readerPageIndex;
      book.scrollOffset = 0;
      book.updatedAt = Date.now();
    }
    this.persistProgress();
    this.resetPageDrag();
  }

  private resetPageDrag(): void {
    this.pageDragAnimationToken++;
    this.pageDragActive = false;
    this.pageDragAnimating = false;
    this.pageDragDx = 0;
    this.pageDragDirection = 0;
    this.pageDragTargetIndex = -1;
    this.pageDragTargetChapter = -1;
    this.pageDragTargetText = '';
  }

  private pageDragTargetX(): number {
    const width = Math.max(1, this.readerViewportWidth);
    return this.pageDragDirection < 0 ? width + this.pageDragDx : -width + this.pageDragDx;
  }

  private pageDragProgress(): number {
    return Math.min(1, Math.abs(this.pageDragDx) / Math.max(1, this.readerViewportWidth));
  }

  private pageLayerText(target: boolean): string {
    return target ? this.pageDragTargetText : this.readerCurrentPageText;
  }

  private pageLayerChapter(target: boolean): number {
    return target ? this.pageDragTargetChapter : this.chapterIndex;
  }

  private pageLayerIndex(target: boolean): number {
    return target ? this.pageDragTargetIndex : this.readerPageIndex;
  }

  private pageLayerTranslation(target: boolean): number {
    return target ? this.pageDragTargetX() : this.pageDragDx;
  }

  private pageLayerOpacity(target: boolean): number {
    return target ? 0.72 + this.pageDragProgress() * 0.28 : 1 - this.pageDragProgress() * 0.22;
  }

  private persistProgress(): void {
    const book = this.currentBook();
    if (book === undefined) {
      return;
    }
    book.currentChapterIndex = this.chapterIndex;
    book.currentPageIndex = this.readerPageIndex;
    book.updatedAt = Date.now();
    book.syncUpdatedAt = book.updatedAt;
    this.recordReadingElapsed();
    LibraryStore.save(this.context(), this.snapshot);
  }

  private recordReadingElapsed(): void {
    if (this.readerSessionStartedAt <= 0) {
      return;
    }
    const now = Date.now();
    const elapsed = now - this.readerSessionStartedAt;
    this.readerSessionStartedAt = now;
    if (elapsed < 1000 || elapsed > 6 * 60 * 60 * 1000) {
      return;
    }
    const key = this.localDateKey(now);
    const record = this.snapshot.dailyReading.find((item: DailyReadingRecord) => item.date === key);
    if (record === undefined) {
      this.snapshot.dailyReading.push(new DailyReadingRecord(key, elapsed));
    } else {
      record.readingMillis += elapsed;
    }
  }

  private localDateKey(time: number): string {
    const date = new Date(time);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  private todayReadingMillis(): number {
    const key = this.localDateKey(Date.now());
    let total = 0;
    this.snapshot.dailyReading.forEach((item: DailyReadingRecord): void => {
      if (item.date === key) total += item.readingMillis;
    });
    return total;
  }

  private totalReadingMillis(): number {
    let total = 0;
    this.snapshot.dailyReading.forEach((item: DailyReadingRecord) => total += item.readingMillis);
    return total;
  }

  private readingStreak(): number {
    let streak = 0;
    const cursor = new Date();
    for (let offset = 0; offset < 365; offset++) {
      const key = this.localDateKey(cursor.getTime());
      const active = this.snapshot.dailyReading.some((item: DailyReadingRecord) => item.date === key &&
        item.readingMillis > 0);
      if (!active) {
        if (offset === 0) {
          cursor.setDate(cursor.getDate() - 1);
          continue;
        }
        break;
      }
      streak++;
      cursor.setDate(cursor.getDate() - 1);
    }
    return streak;
  }

  private formatMinutes(millis: number): string {
    return `${Math.floor(millis / 60000)}分钟`;
  }

  private recentReadingDays(): Array<DailyReadingRecord> {
    const result = new Array<DailyReadingRecord>();
    const cursor = new Date();
    cursor.setDate(cursor.getDate() - 6);
    for (let index = 0; index < 7; index++) {
      const key = this.localDateKey(cursor.getTime());
      let readingMillis = 0;
      this.snapshot.dailyReading.forEach((item: DailyReadingRecord): void => {
        if (item.date === key) readingMillis += item.readingMillis;
      });
      result.push(new DailyReadingRecord(key.substring(5), readingMillis));
      cursor.setDate(cursor.getDate() + 1);
    }
    return result;
  }

  private customCategories(): Array<string> {
    const categories = new Array<string>();
    this.snapshot.books.forEach((book: BookRecord) => {
      const category = book.category.trim().length === 0 ? '未分类' : book.category.trim();
      if (categories.indexOf(category) < 0) {
        categories.push(category);
      }
    });
    categories.sort();
    return categories;
  }

  private saveSelectedBookDetails(): void {
    const book = this.selectedBook();
    const title = this.bookTitleDraft.trim();
    const category = this.bookCategoryDraft.trim().length === 0 ? '未分类' : this.bookCategoryDraft.trim();
    if (book === undefined || title.length === 0) {
      return;
    }
    if (title.length > 80 || category.length > 20) {
      promptAction.showToast({ message: '书名最多 80 字，分类最多 20 字' });
      return;
    }
    if (category === '全部' || category === '正在阅读' || category === '已读完') {
      promptAction.showToast({ message: '该分类名为系统筛选项，请更换名称' });
      return;
    }
    book.title = title;
    book.category = category;
    book.updatedAt = Date.now();
    book.syncUpdatedAt = book.updatedAt;
    LibraryStore.save(this.context(), this.snapshot);
    this.reloadLibrary();
    this.closeUtility();
  }

  private toggleFinished(book: BookRecord): void {
    book.finishedAt = book.finishedAt > 0 ? 0 : Date.now();
    book.updatedAt = Date.now();
    book.syncUpdatedAt = book.updatedAt;
    LibraryStore.save(this.context(), this.snapshot);
    this.reloadLibrary();
  }

  private async exportBackup(): Promise<void> {
    try {
      await BackupService.exportBackup(this.context(), this.snapshot);
      promptAction.showToast({ message: '备份完成' });
    } catch (error) {
      const message = ErrorText.from(error as BusinessError);
      if (message.indexOf('cancel') < 0 && message.indexOf('Cancel') < 0) {
        promptAction.showToast({ message: `备份失败：${message}` });
      }
    }
  }

  private async restoreBackup(): Promise<void> {
    try {
      const count = await BackupService.importBackup(this.context());
      this.reloadLibrary();
      promptAction.showToast({ message: `已恢复 ${count} 本书` });
    } catch (error) {
      const message = ErrorText.from(error as BusinessError);
      if (message.indexOf('cancel') < 0 && message.indexOf('Cancel') < 0) {
        promptAction.showToast({ message: `恢复失败：${message}` });
      }
    }
  }

  private updateScrollOffset(): void {
    const book = this.currentBook();
    if (book !== undefined) {
      const current = this.readerScroller.currentOffset();
      book.scrollOffset = Math.max(0, current.yOffset);
    }
  }

  private closeReader(): void {
    this.persistProgress();
    animateTo({ duration: 180, curve: Curve.EaseIn }, () => this.readerProgress = 0);
    setTimeout(() => {
      this.page = 'shelf';
      this.currentBookId = '';
      this.chapters = [];
      this.reloadLibrary();
    }, 185);
  }

  private changeChapter(index: number): void {
    if (index < 0 || index >= this.chapters.length || index === this.chapterIndex) {
      return;
    }
    const book = this.currentBook();
    if (book !== undefined) {
      book.currentChapterIndex = index;
      book.scrollOffset = 0;
      book.updatedAt = Date.now();
      book.syncUpdatedAt = book.updatedAt;
    }
    this.chapterIndex = index;
    this.closeReaderSelection();
    this.readerPageIndex = 0;
    this.rebuildReaderPages(0);
    if (this.showCatalog) {
      this.closeCatalog();
    }
    this.readerScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.persistProgress();
  }

  private removeBook(book: BookRecord): void {
    AlertDialog.show({
      title: '移除书籍',
      message: `确定从书架移除《${book.title}》吗？本地阅读进度和笔记也会删除。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#C54232',
        action: () => {
          this.recordSyncDeletion('book', book.syncId);
          this.snapshot.books = this.snapshot.books.filter((item: BookRecord) => item.id !== book.id);
          this.snapshot.bookmarks = this.snapshot.bookmarks.filter((item: BookmarkRecord) => item.bookId !== book.id);
          this.snapshot.notes = this.snapshot.notes.filter((item: NoteRecord) => item.bookId !== book.id);
          LibraryStore.deleteBookFiles(this.context(), book.id);
          LibraryStore.save(this.context(), this.snapshot);
          this.books = this.sortedBooks(this.snapshot.books);
        }
      }
    });
  }

  private togglePin(book: BookRecord): void {
    book.pinnedAt = book.pinnedAt > 0 ? 0 : Date.now();
    book.updatedAt = Date.now();
    book.syncUpdatedAt = book.updatedAt;
    LibraryStore.save(this.context(), this.snapshot);
    this.books = this.sortedBooks(this.snapshot.books);
  }

  private chapterProgress(book: BookRecord): number {
    if (book.totalChapters <= 0) {
      return 0;
    }
    if (book.finishedAt > 0) {
      return 100;
    }
    return Math.min(99, Math.floor(book.currentChapterIndex * 100 / book.totalChapters));
  }

  private notesAt(paragraphIndex: number): Array<NoteRecord> {
    return this.snapshot.notes.filter((note: NoteRecord) => note.bookId === this.currentBookId &&
      note.chapterIndex === this.chapterIndex && note.paragraphIndex === paragraphIndex && note.noteText.trim().length > 0);
  }

  private openNoteEditor(paragraphIndex: number, existing: NoteRecord | undefined = undefined,
    selectionStart: number = -1, selectionEnd: number = -1, selectedText: string = ''): void {
    this.noteParagraphIndex = paragraphIndex;
    this.editingNoteId = existing === undefined ? '' : existing.id;
    this.noteDraft = existing === undefined ? '' : existing.noteText;
    this.noteSelectionStart = existing === undefined ? selectionStart : existing.textStartOffset;
    this.noteSelectionEnd = existing === undefined ? selectionEnd : existing.textEndOffset;
    this.noteSelectedText = existing === undefined ? selectedText : existing.selectedText;
    this.noteEditorVisible = true;
    this.noteProgress = 0;
    animateTo({ duration: 280, curve: Curve.Friction }, () => this.noteProgress = 1);
  }

  private closeNoteEditor(): void {
    animateTo({ duration: 180, curve: Curve.EaseIn }, () => this.noteProgress = 0);
    setTimeout((): void => {
      this.noteEditorVisible = false;
    }, 185);
  }

  private saveNote(): void {
    const content = this.noteDraft.trim();
    if (content.length === 0 || this.noteParagraphIndex < 0) {
      return;
    }
    const existing = this.snapshot.notes.find((note: NoteRecord) => note.id === this.editingNoteId);
    if (existing !== undefined) {
      existing.noteText = content;
      existing.paragraphIndex = this.noteParagraphIndex;
      existing.updatedAt = Date.now();
    } else {
      const paragraphs = this.paragraphs();
      const note = new NoteRecord();
      note.id = `${Date.now()}_${this.noteParagraphIndex}`;
      note.bookId = this.currentBookId;
      note.chapterIndex = this.chapterIndex;
      note.paragraphIndex = this.noteParagraphIndex;
      note.selectedText = this.noteSelectedText.length > 0 ? this.noteSelectedText : paragraphs[this.noteParagraphIndex];
      note.noteText = content;
      note.textStartOffset = this.noteSelectionStart;
      note.textEndOffset = this.noteSelectionEnd;
      note.createdAt = Date.now();
      note.updatedAt = note.createdAt;
      this.snapshot.notes.push(note);
    }
    LibraryStore.save(this.context(), this.snapshot);
    this.snapshot = LibraryStore.load(this.context());
    this.closeNoteEditor();
    this.noteDraft = '';
  }

  private deleteEditingNote(): void {
    if (this.editingNoteId.length === 0) {
      this.closeNoteEditor();
      return;
    }
    const removed = this.snapshot.notes.find((note: NoteRecord): boolean => note.id === this.editingNoteId);
    if (removed !== undefined) {
      this.recordSyncDeletion('note', removed.syncId);
    }
    this.snapshot.notes = this.snapshot.notes.filter((note: NoteRecord) => note.id !== this.editingNoteId);
    LibraryStore.save(this.context(), this.snapshot);
    this.snapshot = LibraryStore.load(this.context());
    this.closeNoteEditor();
  }

  private isCurrentBookmarked(): boolean {
    const book = this.currentBook();
    return this.snapshot.bookmarks.some((bookmark: BookmarkRecord): boolean => {
      if (bookmark.bookId !== this.currentBookId || bookmark.chapterIndex !== this.chapterIndex) return false;
      return this.readerReadMode === 0 ? bookmark.pageIndex === this.readerPageIndex :
        book !== undefined && Math.abs(bookmark.scrollOffset - book.scrollOffset) < 80;
    });
  }

  private toggleBookmark(): void {
    const book = this.currentBook();
    const existing = this.snapshot.bookmarks.find((bookmark: BookmarkRecord): boolean => {
      if (bookmark.bookId !== this.currentBookId || bookmark.chapterIndex !== this.chapterIndex) return false;
      return this.readerReadMode === 0 ? bookmark.pageIndex === this.readerPageIndex :
        book !== undefined && Math.abs(bookmark.scrollOffset - book.scrollOffset) < 80;
    });
    if (existing !== undefined) {
      this.recordSyncDeletion('bookmark', existing.syncId);
      this.snapshot.bookmarks = this.snapshot.bookmarks.filter((bookmark: BookmarkRecord) => bookmark.id !== existing.id);
    } else {
      const bookmark = new BookmarkRecord();
      bookmark.id = `${Date.now()}_${this.chapterIndex}`;
      bookmark.bookId = this.currentBookId;
      bookmark.chapterIndex = this.chapterIndex;
      bookmark.pageIndex = this.readerPageIndex;
      bookmark.chapterTitle = this.currentChapter().title;
      const summarySource = this.readerReadMode === 0 ? this.currentPagedText() : this.currentChapter().content;
      bookmark.summary = summarySource.substring(0, Math.min(80, summarySource.length)).trim();
      bookmark.createdAt = Date.now();
      bookmark.updatedAt = bookmark.createdAt;
      bookmark.scrollOffset = book === undefined ? 0 : book.scrollOffset;
      this.snapshot.bookmarks.push(bookmark);
    }
    LibraryStore.save(this.context(), this.snapshot);
    this.snapshot = LibraryStore.load(this.context());
  }

  private saveSettings(): void {
    this.snapshot.settings.textSize = this.readerTextSize;
    this.snapshot.settings.lineHeight = this.readerLineHeight;
    this.snapshot.settings.themeMode = this.readerThemeMode;
    this.snapshot.settings.pageMargin = this.readerPageMargin;
    this.snapshot.settings.readMode = this.readerReadMode;
    this.snapshot.settingsUpdatedAt = Date.now();
    LibraryStore.save(this.context(), this.snapshot);
    this.snapshot = LibraryStore.load(this.context());
  }

  private recordSyncDeletion(type: string, syncId: string): void {
    if (syncId === undefined || syncId.length === 0) {
      return;
    }
    const existing = this.snapshot.syncTombstones.find((item: SyncTombstoneRecord): boolean =>
      item.type === type && item.syncId === syncId);
    if (existing !== undefined) {
      existing.deletedAt = Date.now();
      return;
    }
    const tombstone = new SyncTombstoneRecord();
    tombstone.type = type;
    tombstone.syncId = syncId;
    tombstone.deletedAt = Date.now();
    this.snapshot.syncTombstones.push(tombstone);
  }

  private settings(): ReaderSettings {
    return this.snapshot.settings;
  }

  private readerBackground(): string {
    switch (this.readerThemeMode) {
      case 1:
        return '#E7E1CF';
      case 2:
        return '#DDE8DD';
      case 3:
        return '#1D211F';
      default:
        return '#F7F4ED';
    }
  }

  private readerTextColor(): string {
    return this.readerThemeMode === 3 ? '#D7D9D7' : '#282A27';
  }

  @Builder
  private ShelfPage() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Image($r('app.media.bookshelf_bg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .opacity(this.backgroundOpacity)

      Column() {
        if (this.mainTab === 'shelf') {
          Column() {
            Row() {
              Text(`累计阅读${this.formatMinutes(this.totalReadingMillis())}`)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#111111')
                .layoutWeight(1)
              Text(`连续${this.readingStreak()}天`)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .textAlign(TextAlign.Center)
                .width(72)
                .height(30)
                .borderRadius(15)
                .backgroundColor('#DDB95A52')
              Text('◷')
                .fontSize(25)
                .fontColor('#111111')
                .textAlign(TextAlign.Center)
                .width(42)
                .onClick(() => this.openUtility('history'))
              Text(this.searchVisible ? '×' : '⌕')
                .fontSize(30)
                .fontColor('#111111')
                .textAlign(TextAlign.Center)
                .width(48)
                .onClick(() => {
                  animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
                    this.searchVisible = !this.searchVisible;
                    if (!this.searchVisible) {
                      this.searchQuery = '';
                    }
                  });
                })
              Text('···')
                .fontSize(30)
                .fontColor('#111111')
                .textAlign(TextAlign.Center)
                .width(48)
                .onClick(() => this.toggleMoreMenu())
            }
            .height(64)
            .width('100%')

            if (this.searchVisible) {
              TextInput({ text: this.searchQuery, placeholder: '搜索书名、作者、分类或简介' })
                .height(44)
                .fontSize(16)
                .backgroundColor('#EFFFFFFF')
                .borderRadius(22)
                .padding({ left: 18, right: 18 })
                .margin({ bottom: 12 })
                .onChange((value: string) => this.searchQuery = value)
            }

            if (this.visibleBooks().length === 0) {
              Column() {
                Text(this.searchQuery.length > 0 ? '没有匹配的书籍' :
                  (this.categoryFilter !== '全部' ? '当前筛选下没有书籍' : '书架还是空的'))
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#333333')
                Button(this.searchQuery.length > 0 ? '清除搜索' :
                  (this.categoryFilter !== '全部' ? '查看全部书籍' : '本机导入'))
                  .fontColor('#111111')
                  .backgroundColor('#CFFFFFFF')
                  .margin({ top: 18 })
                  .onClick(() => {
                    if (this.searchQuery.length > 0) {
                      this.searchQuery = '';
                    } else if (this.categoryFilter !== '全部') {
                      this.categoryFilter = '全部';
                    } else {
                      this.importBooks();
                    }
                  })
              }
              .justifyContent(FlexAlign.Center)
              .width('100%')
              .layoutWeight(1)
            } else if (this.gridMode) {
              Grid() {
                ForEach(this.visibleBooks(), (book: BookRecord) => {
                  GridItem() {
                    Column() {
                      Stack({ alignContent: Alignment.TopEnd }) {
                        Column() {
                          Text(book.title.substring(0, Math.min(12, book.title.length)))
                            .fontSize(17)
                            .fontWeight(FontWeight.Bold)
                            .fontColor('#111111')
                            .textAlign(TextAlign.Center)
                            .maxLines(3)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                          Text(`${book.author} · ${book.fileType.toUpperCase()}`)
                            .fontSize(12)
                            .fontColor('#333333')
                            .maxLines(1)
                            .margin({ top: 14 })
                        }
                        .justifyContent(FlexAlign.Center)
                        .width('100%')
                        .height(142)
                        .backgroundColor('#55FFFFFF')
                        if (book.pinnedAt > 0) {
                          Text('◆')
                            .fontSize(20)
                            .fontColor('#B95A52')
                            .margin({ top: 4, right: 6 })
                        }
                      }
                      Text(book.title)
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#111111')
                        .maxLines(2)
                        .width('100%')
                        .margin({ top: 10 })
                      Text(`阅读进度 ${this.chapterProgress(book)}% · ${book.totalChapters}章`)
                        .fontSize(12)
                        .fontColor('#333333')
                        .maxLines(1)
                        .width('100%')
                        .margin({ top: 4 })
                    }
                    .padding(8)
                    .width('100%')
                    .backgroundColor('#BFFFFFFF')
                    .borderRadius(4)
                    .border({ width: 1, color: '#80FFFFFF' })
                    .shadow({ radius: 7, color: '#33000000', offsetY: 3 })
                    .onClick(() => this.openBook(book))
                    .gesture(LongPressGesture().onAction(() => {
                      this.openBookActions(book);
                    }))
                  }
                }, (book: BookRecord) => this.bookRenderKey(book))
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(12)
              .rowsGap(28)
              .padding({ left: 2, right: 2, top: 8, bottom: 16 })
              .layoutWeight(1)
            } else {
              List({ space: 12 }) {
                ForEach(this.visibleBooks(), (book: BookRecord) => {
                  ListItem() {
                    Column() {
                      Row() {
                        Text(book.title)
                          .fontSize(17)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#111111')
                          .maxLines(2)
                          .layoutWeight(1)
                        Text(book.pinnedAt > 0 ? '◆' : '')
                          .fontColor('#B95A52')
                      }
                      Text(`${book.author} · ${book.fileType.toUpperCase()} · ${book.totalChapters}章`)
                        .fontSize(14)
                        .fontColor('#333333')
                        .width('100%')
                        .margin({ top: 6 })
                      Text(`阅读进度 ${this.chapterProgress(book)}%`)
                        .fontSize(12)
                        .fontColor('#333333')
                        .width('100%')
                        .margin({ top: 10 })
                    }
                    .padding(16)
                    .width('100%')
                    .backgroundColor('#BFFFFFFF')
                    .borderRadius(8)
                    .border({ width: 1, color: '#80FFFFFF' })
                    .onClick(() => this.openBook(book))
                    .gesture(LongPressGesture().onAction(() => {
                      this.openBookActions(book);
                    }))
                  }
                }, (book: BookRecord) => this.bookRenderKey(book))
              }
              .layoutWeight(1)
            }
          }
          .layoutWeight(1)
          .width('100%')
        } else {
          this.HomePage()
        }

        Row() {
          Text('书架')
            .fontSize(16)
            .fontWeight(this.mainTab === 'shelf' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.mainTab === 'shelf' ? '#B95A52' : '#111111')
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(52)
            .onClick(() => this.switchMainTab('shelf'))
          Text('主页')
            .fontSize(16)
            .fontWeight(this.mainTab === 'home' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.mainTab === 'home' ? '#B95A52' : '#111111')
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(52)
            .onClick(() => this.switchMainTab('home'))
        }
        .width('100%')
        .height(56)
        .backgroundColor('#EFFFFFFF')
        .borderRadius(28)
        .margin({ bottom: 10 })
        .shadow({ radius: 8, color: '#33000000', offsetY: 3 })
      }
      .padding({ left: 20, right: 20 })
      .safeAreaPadding({ top: 8 })
      .width('100%')
      .height('100%')
      .opacity(this.pageProgress)
      .translate({ x: (1 - this.pageProgress) * (this.mainTab === 'shelf' ? -20 : 20) })

      if (this.moreMenuVisible) {
        Column() {
          Text(this.importing ? '导入中…' : '本机导入')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => {
              this.toggleMoreMenu();
              this.importBooks();
            })
          Text(this.gridMode ? '切换列表视图' : '切换网格视图')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => {
              this.toggleGridMode();
            })
          Text('导入记录')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => this.openUtility('imports'))
          Text('书架排序')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => this.cycleSortMode())
          Text('分类筛选')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => this.openUtility('category'))
          Text('阅读统计')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => this.openUtility('stats'))
          Text('阅读目标')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => this.openUtility('goal'))
          Text('书架背景')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => this.openUtility('background'))
          Text('备份数据')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => {
              this.toggleMoreMenu();
              this.exportBackup();
            })
          Text('恢复数据')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => {
              this.toggleMoreMenu();
              this.restoreBackup();
            })
          Text('在线搜书')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => {
              this.openOnlineSearch();
            })
          Text('内置浏览器')
            .fontSize(16)
            .fontColor('#111111')
            .width('100%')
            .height(52)
            .padding({ left: 18 })
            .onClick(() => this.openBrowser())
        }
        .width(220)
        .padding({ top: 10, bottom: 10 })
        .backgroundColor('#F8FFFFFF')
        .borderRadius(14)
        .shadow({ radius: 18, color: '#44000000', offsetY: 6 })
        .margin({ top: 76, right: 20 })
        .opacity(this.moreMenuProgress)
        .scale({ x: 0.88 + this.moreMenuProgress * 0.12, y: 0.88 + this.moreMenuProgress * 0.12 })
        .translate({ y: (1 - this.moreMenuProgress) * -12 })
      }

      if (this.utilityPage.length > 0) {
        this.UtilityPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F4F1')
  }

  @Builder
  private HomePage() {
    Scroll() {
      Column() {
        Row() {
          Text('主页')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111111')
            .layoutWeight(1)
          Text(this.snapshot.userName.length > 0 ? this.snapshot.userName.substring(0, 1) : '默')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.Center)
            .width(56)
            .height(56)
            .borderRadius(28)
            .backgroundColor('#7D9185')
            .onClick(() => this.openUtility('profile'))
        }
        .width('100%')
        Text(`今日目标 ${Math.floor(this.todayReadingMillis() / 60000)}/${this.snapshot.readingGoalMinutes}分钟 · ${Math.min(100,
          Math.floor(this.todayReadingMillis() / Math.max(1, this.snapshot.readingGoalMinutes * 60000) * 100))}%`)
          .fontSize(16)
          .fontColor('#111111')
          .width('100%')
          .margin({ top: 8 })

        Row() {
          this.HomeStat(`${this.snapshot.books.length}本`, '全部书籍')
          this.HomeStat(`${this.snapshot.books.filter((book: BookRecord) => book.finishedAt === 0).length}本`, '正在阅读')
          this.HomeStat(`${this.snapshot.books.filter((book: BookRecord) => book.finishedAt > 0).length}本`, '已读完')
        }
        .width('100%')
        .padding(18)
        .backgroundColor('#DFFFFFFF')
        .borderRadius(18)
        .shadow({ radius: 8, color: '#26000000', offsetY: 3 })
        .margin({ top: 24 })

        Text('常用功能')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111111')
          .width('100%')
          .margin({ top: 26, bottom: 6 })
        this.HomeAction('阅读统计', '查看近七天与累计阅读', () => this.openUtility('stats'))
        this.HomeAction('每日阅读目标', `当前 ${this.snapshot.readingGoalMinutes} 分钟`, () => this.openUtility('goal'))
        this.HomeAction('最近阅读', '继续上次阅读的小说', () => this.openUtility('history'))
        this.HomeAction('本机导入', '导入 TXT 或 EPUB', () => {
          this.importBooks();
        })
        this.HomeAction('在线搜书', '选书源搜索并以 TXT / EPUB 后台下载', () => this.openOnlineSearch())
        this.HomeAction('内置浏览器', '浏览小说站点并直接进入在线阅读', () => this.openBrowser())
        this.HomeAction('WebDAV 同步', '与安卓端同步书籍、进度、书签和笔记', () => this.openUtility('webdav'))
        this.HomeAction('备份数据', '导出书籍、进度、书签与笔记', () => {
          this.exportBackup();
        })
        this.HomeAction('恢复数据', '从 NovelReader JSON 备份恢复', () => {
          this.restoreBackup();
        })
      }
      .width('100%')
      .padding({ top: 28, bottom: 24 })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private HomeStat(value: string, label: string) {
    Column() {
      Text(value).fontSize(21).fontWeight(FontWeight.Bold).fontColor('#111111')
      Text(label).fontSize(13).fontColor('#333333').margin({ top: 4 })
    }
    .layoutWeight(1)
  }

  @Builder
  private HomeAction(title: string, subtitle: string, action: () => void) {
    Row() {
      Column() {
        Text(title).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#111111')
        Text(subtitle).fontSize(13).fontColor('#666666').margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›').fontSize(28).fontColor('#777777')
    }
    .width('100%')
    .height(64)
    .padding({ left: 18, right: 18 })
    .backgroundColor('#DFFFFFFF')
    .borderRadius(14)
    .margin({ top: 10 })
    .onClick(action)
  }

  @Builder
  private UtilityPanel() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
      }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .opacity(this.utilityProgress)
        .onClick(() => this.closeUtility())

      Column() {
        Row() {
          Text(this.utilityPage === 'stats' ? '阅读统计' : this.utilityPage === 'history' ? '最近阅读' :
            this.utilityPage === 'goal' ? '每日阅读目标' : this.utilityPage === 'category' ? '分类筛选' :
              this.utilityPage === 'imports' ? '导入记录' : this.utilityPage === 'background' ? '书架背景' :
                this.utilityPage === 'online' ? '在线搜书' : this.utilityPage === 'webdav' ? 'WebDAV 同步' :
                  this.utilityPage === 'profile' ? '个人与设置' : '书籍管理')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1E211F')
            .layoutWeight(1)
          Text('×')
            .fontSize(28)
            .fontColor('#68706A')
            .width(44)
            .textAlign(TextAlign.Center)
            .onClick(() => this.closeUtility())
        }
        .width('100%')

        if (this.utilityPage === 'stats') {
          Row() {
            this.HomeStat(this.formatMinutes(this.todayReadingMillis()), '今日阅读')
            this.HomeStat(this.formatMinutes(this.totalReadingMillis()), '累计阅读')
            this.HomeStat(`${this.readingStreak()}天`, '连续阅读')
          }
          .width('100%')
          .margin({ top: 22 })
          Text('最近 7 天')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#303632')
            .width('100%')
            .margin({ top: 26, bottom: 10 })
          Row() {
            ForEach(this.recentReadingDays(), (day: DailyReadingRecord) => {
              Column() {
                Text(`${Math.floor(day.readingMillis / 60000)}`)
                  .fontSize(11)
                  .fontColor('#68706A')
                Blank()
                  .width(18)
                  .height(Math.min(100, Math.max(4, Math.floor(day.readingMillis / 60000) * 3)))
                  .backgroundColor('#6E8D7B')
                  .borderRadius({ topLeft: 6, topRight: 6 })
                  .margin({ top: 5 })
                Text(day.date)
                  .fontSize(11)
                  .fontColor('#68706A')
                  .margin({ top: 6 })
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.End)
            }, (day: DailyReadingRecord) => day.date)
          }
          .height(150)
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          .padding({ left: 4, right: 4 })
        } else if (this.utilityPage === 'history') {
          if (this.snapshot.books.length === 0) {
            Text('还没有阅读记录')
              .fontSize(16)
              .fontColor('#777777')
              .margin({ top: 36, bottom: 36 })
          } else {
            List({ space: 4 }) {
              ForEach(this.sortedBooks(this.snapshot.books).slice(0, 10), (book: BookRecord) => {
                ListItem() {
                  Row() {
                    Column() {
                      Text(book.title)
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#242824')
                        .maxLines(1)
                      Text(`进度 ${book.currentChapterIndex + 1}/${book.totalChapters} · ${this.chapterProgress(book)}%`)
                        .fontSize(13)
                        .fontColor('#707670')
                        .margin({ top: 5 })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Text('›').fontSize(26).fontColor('#777777')
                  }
                  .height(66)
                  .width('100%')
                  .padding({ left: 4, right: 4 })
                  .onClick(() => {
                    this.closeUtility();
                    setTimeout((): void => {
                      this.openBook(book);
                    }, 180);
                  })
                }
              }, (book: BookRecord) => this.bookRenderKey(book))
            }
            .height(480)
            .width('100%')
            .margin({ top: 14 })
          }
        } else if (this.utilityPage === 'goal') {
          Text(`${this.snapshot.readingGoalMinutes} 分钟`)
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#456653')
            .margin({ top: 38 })
          Text('每天留一点时间给阅读')
            .fontSize(14)
            .fontColor('#737A75')
            .margin({ top: 6, bottom: 24 })
          Slider({ value: this.snapshot.readingGoalMinutes, min: 5, max: 180, step: 5 })
            .selectedColor('#486555')
            .onChange((value: number) => {
              const changed = JSON.parse(JSON.stringify(this.snapshot)) as LibrarySnapshot;
              changed.readingGoalMinutes = Math.round(value);
              this.snapshot = LibraryStore.normalizeSnapshot(changed);
              LibraryStore.save(this.context(), this.snapshot);
            })
          Row() {
            ForEach([15, 30, 60, 90], (minutes: number) => {
              Text(`${minutes}分`)
                .fontSize(14)
                .fontColor(this.snapshot.readingGoalMinutes === minutes ? '#FFFFFF' : '#465049')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .backgroundColor(this.snapshot.readingGoalMinutes === minutes ? '#486555' : '#EEF1ED')
                .margin({ right: minutes < 90 ? 8 : 0 })
                .onClick(() => {
                  this.snapshot.readingGoalMinutes = minutes;
                  LibraryStore.save(this.context(), this.snapshot);
                  this.snapshot = LibraryStore.load(this.context());
                })
            })
          }
          .width('100%')
          .margin({ top: 24, bottom: 28 })
        } else if (this.utilityPage === 'category') {
          List({ space: 4 }) {
            ForEach(['全部', '正在阅读', '已读完'].concat(this.customCategories()), (category: string) => {
              ListItem() {
                Row() {
                  Text(category)
                    .fontSize(16)
                    .fontColor('#252A26')
                    .layoutWeight(1)
                  Text(this.categoryFilter === category ? '✓' : '')
                    .fontSize(18)
                    .fontColor('#486555')
                }
                .height(54)
                .width('100%')
                .padding({ left: 6, right: 6 })
                .onClick(() => {
                  this.categoryFilter = category;
                  this.closeUtility();
                })
              }
            }, (category: string) => category)
          }
          .height(420)
          .width('100%')
          .margin({ top: 12 })
        } else if (this.utilityPage === 'imports') {
          if (this.snapshot.books.length === 0) {
            Text('还没有导入记录')
              .fontSize(16)
              .fontColor('#777777')
              .margin({ top: 36, bottom: 36 })
          } else {
            List({ space: 4 }) {
              ForEach(this.snapshot.books.slice().sort((left: BookRecord, right: BookRecord) =>
                right.createdAt - left.createdAt), (book: BookRecord) => {
                ListItem() {
                  Column() {
                    Text(book.title)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#252A26')
                      .width('100%')
                    Text(`${book.fileType.toUpperCase()} · ${book.totalChapters}章 · ${this.localDateKey(book.createdAt)}`)
                      .fontSize(13)
                      .fontColor('#747B76')
                      .width('100%')
                      .margin({ top: 5 })
                  }
                  .height(64)
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                }
              }, (book: BookRecord) => this.bookRenderKey(book))
            }
            .height(420)
            .width('100%')
            .margin({ top: 12 })
          }
        } else if (this.utilityPage === 'background') {
          Text(`背景透明度 ${Math.round(this.backgroundOpacity * 100)}%`)
            .fontSize(16)
            .fontColor('#39423C')
            .width('100%')
            .margin({ top: 26, bottom: 12 })
          Slider({ value: this.backgroundOpacity, min: 0.15, max: 0.95, step: 0.05 })
            .selectedColor('#486555')
            .onChange((value: number) => this.backgroundOpacity = value)
          Row() {
            ForEach([0.3, 0.5, 0.7, 0.9], (alpha: number) => {
              Text(`${Math.round(alpha * 100)}%`)
                .fontSize(14)
                .fontColor(Math.abs(this.backgroundOpacity - alpha) < 0.01 ? '#FFFFFF' : '#465049')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .backgroundColor(Math.abs(this.backgroundOpacity - alpha) < 0.01 ? '#486555' : '#EEF1ED')
                .margin({ right: alpha < 0.9 ? 8 : 0 })
                .onClick(() => this.backgroundOpacity = alpha)
            })
          }
          .width('100%')
          .margin({ top: 22, bottom: 24 })
        } else if (this.utilityPage === 'online') {
          Text('使用与安卓版本相同的在线书源规则，选择结果后会下载全部章节并直接加入书架。')
            .fontSize(14)
            .fontColor('#6B736E')
            .width('100%')
            .margin({ top: 20, bottom: 14 })
          TextInput({ text: this.onlineKeyword, placeholder: '书名或作者' })
            .height(50)
            .fontSize(16)
            .backgroundColor('#F1F3EF')
            .borderRadius(12)
            .onChange((value: string) => this.onlineKeyword = value)
          Button(this.onlineBusy ? '搜索中…' : '开始搜索')
            .width('100%')
            .height(48)
            .fontColor('#FFFFFF')
            .backgroundColor('#486555')
            .margin({ top: 14, bottom: 10 })
            .enabled(!this.onlineBusy && this.onlineDownloadingUrl.length === 0)
            .onClick((): void => {
              this.searchOnline();
            })
          if (this.onlineStatus.length > 0) {
            Text(this.onlineStatus)
              .fontSize(13)
              .fontColor(this.onlineStatus.startsWith('下载失败') || this.onlineStatus.startsWith('搜索失败') ? '#B74434' : '#5E6862')
              .width('100%')
              .margin({ top: 4, bottom: 8 })
          }
          if (this.onlineResults.length > 0) {
            List({ space: 8 }) {
              ForEach(this.onlineResults, (result: OnlineBookResult) => {
                ListItem() {
                  Column() {
                    Row() {
                      Column() {
                        Text(result.bookName)
                          .fontSize(16)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#252A26')
                          .maxLines(1)
                        Text(`${result.author.length > 0 ? result.author : '未知作者'} · ${result.sourceName}`)
                          .fontSize(12)
                          .fontColor('#737A75')
                          .margin({ top: 4 })
                          .maxLines(1)
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      Button(this.onlineDownloadingUrl === result.url ? '下载中' : '下载')
                        .height(36)
                        .fontSize(13)
                        .fontColor('#FFFFFF')
                        .backgroundColor('#486555')
                        .enabled(this.onlineDownloadingUrl.length === 0 && !this.onlineBusy)
                        .onClick((): void => {
                          this.downloadOnline(result);
                        })
                    }
                    .width('100%')
                    if (result.latestChapter.length > 0) {
                      Text(`最新：${result.latestChapter}`)
                        .fontSize(12)
                        .fontColor('#747B76')
                        .maxLines(1)
                        .width('100%')
                        .margin({ top: 6 })
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor('#F1F3EF')
                  .borderRadius(12)
                }
              }, (result: OnlineBookResult) => `${result.sourceId}_${result.url}`)
            }
            .height(390)
            .width('100%')
            .margin({ top: 6 })
          }
        } else if (this.utilityPage === 'webdav') {
          Text('同步目录和数据格式与安卓版本一致：NovelReaderSync/manifest.json（schema 1）、书籍对象包、阅读进度、书签和笔记可双向互通。')
            .fontSize(14)
            .fontColor('#6B736E')
            .width('100%')
            .margin({ top: 18, bottom: 12 })
          TextInput({ text: this.webDavUrl, placeholder: 'WebDAV 地址，例如 https://dav.example.com/user/' })
            .height(48)
            .fontSize(15)
            .backgroundColor('#F1F3EF')
            .borderRadius(12)
            .onChange((value: string): void => {
              this.webDavUrl = value;
            })
          TextInput({ text: this.webDavUsername, placeholder: '用户名' })
            .height(48)
            .fontSize(15)
            .backgroundColor('#F1F3EF')
            .borderRadius(12)
            .margin({ top: 10 })
            .onChange((value: string): void => {
              this.webDavUsername = value;
            })
          TextInput({ text: this.webDavPassword, placeholder: '应用密码' })
            .type(InputType.Password)
            .height(48)
            .fontSize(15)
            .backgroundColor('#F1F3EF')
            .borderRadius(12)
            .margin({ top: 10 })
            .onChange((value: string): void => {
              this.webDavPassword = value;
            })
          if (this.webDavStatus.length > 0) {
            Text(`${this.webDavStatus}${this.webDavBusy ? ` · ${this.webDavProgress}%` : ''}`)
              .fontSize(13)
              .fontColor(this.webDavStatus.indexOf('失败') >= 0 ? '#B74434' : '#5E6862')
              .width('100%')
              .margin({ top: 12 })
          }
          Row() {
            Button('保存')
              .layoutWeight(1)
              .height(44)
              .fontColor('#3E4A43')
              .backgroundColor('#EDF1EC')
              .enabled(!this.webDavBusy)
              .onClick((): void => this.saveWebDav())
            Button('测试连接')
              .layoutWeight(1)
              .height(44)
              .fontColor('#3E4A43')
              .backgroundColor('#EDF1EC')
              .margin({ left: 10 })
              .enabled(!this.webDavBusy)
              .onClick((): void => {
                this.testWebDav();
              })
          }
          .width('100%')
          .margin({ top: 14 })
          Button(this.webDavBusy ? '同步中…' : '立即双向同步')
            .width('100%')
            .height(48)
            .fontColor('#FFFFFF')
            .backgroundColor('#486555')
            .margin({ top: 10, bottom: 8 })
            .enabled(!this.webDavBusy)
            .onClick((): void => {
              this.syncWebDav();
            })
        } else if (this.utilityPage === 'profile') {
          TextInput({ text: this.profileNameDraft, placeholder: '昵称' })
            .height(50)
            .fontSize(16)
            .backgroundColor('#F1F3EF')
            .borderRadius(12)
            .margin({ top: 20 })
            .onChange((value: string) => this.profileNameDraft = value)
          Button('保存昵称')
            .width('100%')
            .height(46)
            .fontColor('#FFFFFF')
            .backgroundColor('#486555')
            .margin({ top: 12 })
            .onClick(() => this.saveProfile())
          Button('清除阅读统计')
            .width('100%')
            .height(46)
            .fontColor('#B74434')
            .backgroundColor('#F8ECE9')
            .margin({ top: 12 })
            .onClick(() => this.confirmClearReadingStats())
          Text('小说阅读器 HarmonyOS\n支持 TXT / EPUB 本地阅读、书签、笔记、统计和备份恢复。')
            .fontSize(14)
            .fontColor('#737A75')
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 24, bottom: 12 })
        } else if (this.utilityPage === 'book') {
          TextInput({ text: this.bookTitleDraft, placeholder: '书名' })
            .maxLength(80)
            .height(48)
            .fontSize(16)
            .backgroundColor('#F1F3EF')
            .borderRadius(12)
            .margin({ top: 18 })
            .onChange((value: string) => this.bookTitleDraft = value)
          TextInput({ text: this.bookCategoryDraft, placeholder: '分类' })
            .maxLength(20)
            .height(48)
            .fontSize(16)
            .backgroundColor('#F1F3EF')
            .borderRadius(12)
            .margin({ top: 12, bottom: 8 })
            .onChange((value: string) => this.bookCategoryDraft = value)
          Button('保存书名与分类')
            .width('100%')
            .height(46)
            .fontColor('#FFFFFF')
            .backgroundColor('#486555')
            .margin({ top: 10 })
            .onClick(() => this.saveSelectedBookDetails())
          if (this.selectedBook() !== undefined) {
            Button(this.selectedBookPinned() ? '取消置顶' : '置顶书籍')
              .width('100%')
              .height(46)
              .fontColor('#3E4A43')
              .backgroundColor('#EDF1EC')
              .margin({ top: 10 })
              .onClick(() => this.toggleSelectedBookPin())
            Button(this.selectedBookFinished() ? '标为正在阅读' : '标为已读完')
              .width('100%')
              .height(46)
              .fontColor('#3E4A43')
              .backgroundColor('#EDF1EC')
              .margin({ top: 10 })
              .onClick(() => this.toggleSelectedBookFinished())
            Button('移除书籍')
              .width('100%')
              .height(46)
              .fontColor('#B74434')
              .backgroundColor('#F8ECE9')
              .margin({ top: 10, bottom: 8 })
              .onClick((): void => {
                const book = this.selectedBook();
                this.closeUtility();
                if (book !== undefined) {
                  setTimeout((): void => {
                    this.removeBook(book);
                  }, 180);
                }
              })
          }
        }
      }
      .width('92%')
      .padding({ left: 22, right: 22, top: 20, bottom: 20 })
      .backgroundColor('#FCFDFB')
      .borderRadius(22)
      .shadow({ radius: 22, color: '#44000000', offsetY: 8 })
      .opacity(this.utilityProgress)
      .scale({ x: 0.92 + this.utilityProgress * 0.08, y: 0.92 + this.utilityProgress * 0.08 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ReaderSelectionMenu() {
    Column() {
      Row() {
        Text(this.readerSelectionHasMark() ? '删除标记' : '标记')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .height(42)
          .padding({ left: 18, right: 18 })
          .textAlign(TextAlign.Center)
          .onClick((): void => {
            if (this.readerSelectionHasMark()) {
              this.deleteReaderMarks();
            } else {
              this.readerSelectionColorVisible = !this.readerSelectionColorVisible;
            }
          })
        Text('复制')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .height(42)
          .padding({ left: 18, right: 18 })
          .textAlign(TextAlign.Center)
          .onClick((): void => {
            this.copyReaderSelection();
          })
        Text('评论')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .height(42)
          .padding({ left: 18, right: 18 })
          .textAlign(TextAlign.Center)
          .onClick((): void => this.commentReaderSelection())
      }
      if (this.readerSelectionColorVisible) {
        Row({ space: 12 }) {
          ForEach(['#E35D5B', '#DDAA43', '#4B87D6', '#4D9B69', '#D56B9A'], (color: string) => {
            Text('━━')
              .fontSize(18)
              .fontColor(color)
              .width(34)
              .height(32)
              .textAlign(TextAlign.Center)
              .onClick((): void => this.saveReaderMark(color))
          }, (color: string): string => color)
        }
        .padding({ left: 10, right: 10, bottom: 6 })
      }
    }
    .backgroundColor('#F02E2E2E')
    .borderRadius(12)
    .shadow({ radius: 10, color: '#55000000', offsetY: 4 })
  }

  private currentPageBodyText(): string {
    const fullText = this.readerCurrentPageText;
    if (this.readerPageIndex !== 0) {
      return fullText;
    }
    const titleLength = Math.min(fullText.length, this.currentChapter().title.length);
    return fullText.substring(titleLength).trim();
  }

  private currentPageBodyAbsoluteStart(): number {
    const fullText = this.readerCurrentPageText;
    const body = this.currentPageBodyText();
    const localStart = body.length === 0 ? Math.min(fullText.length, this.currentChapter().title.length) :
      Math.max(0, fullText.indexOf(body, Math.min(fullText.length, this.currentChapter().title.length)));
    return this.currentPageAbsoluteStart() + localStart;
  }

  private currentSelectablePageText(): string {
    return this.readerPageIndex === 0 ? this.currentPageBodyText() : this.readerCurrentPageText;
  }

  private currentSelectablePageAbsoluteStart(): number {
    return this.readerPageIndex === 0 ? this.currentPageBodyAbsoluteStart() : this.currentPageAbsoluteStart();
  }

  @Builder
  private PagedText() {
    Text(undefined, { controller: this.currentPagedTextController() }) {
      ForEach(this.readerTextSegments(this.currentSelectablePageText(),
        this.currentSelectablePageAbsoluteStart(), this.chapterIndex),
        (segment: ReaderTextSegment, index: number) => {
          if (segment.marked) {
            Span(segment.text)
              .decoration({ type: TextDecorationType.Underline, color: segment.color })
          } else {
            Span(segment.text)
          }
        }, (segment: ReaderTextSegment, index: number): string =>
          `${this.currentSelectablePageAbsoluteStart()}_${index}_${segment.text.length}`)
    }
    .fontSize(this.readerTextSize)
    .fontColor(this.readerTextColor())
    .lineHeight(this.readerTextSize * this.readerLineHeight)
    .width('100%')
    .id(`reader_page_${this.chapterIndex}_${this.readerPageIndex}_${this.currentSelectablePageAbsoluteStart()}`)
    .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
    .copyOption(CopyOptions.LocalDevice)
    .bindSelectionMenu(TextSpanType.TEXT, this.ReaderSelectionMenu, TextResponseType.LONG_PRESS, {
      onAppear: (): void => this.showReaderSelectionMenu(),
      onDisappear: (): void => this.hideReaderSelectionMenu()
    })
    .onTextSelectionChange((selectionStart: number, selectionEnd: number): void => {
      this.updateReaderSelection(this.currentSelectablePageText(), this.currentSelectablePageAbsoluteStart(),
        this.currentPagedTextController(), selectionStart, selectionEnd);
    })
  }

  @Builder
  private PagedLayer(target: boolean) {
    Column() {
      if (this.pageLayerIndex(target) === 0 && this.pageLayerChapter(target) >= 0 &&
        this.pageLayerChapter(target) < this.chapters.length) {
        Text(this.chapters[this.pageLayerChapter(target)].title)
          .fontSize(this.readerTextSize + 5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.readerTextColor())
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ bottom: 28 })
        if (target) {
          Text(this.pageLayerText(true).substring(Math.min(this.pageLayerText(true).length,
            this.chapters[this.pageLayerChapter(true)].title.length)).trim())
            .fontSize(this.readerTextSize)
            .fontColor(this.readerTextColor())
            .lineHeight(this.readerTextSize * this.readerLineHeight)
            .width('100%')
        } else {
          this.PagedText()
        }
      } else {
        if (target) {
          Text(this.pageLayerText(true))
            .fontSize(this.readerTextSize)
            .fontColor(this.readerTextColor())
            .lineHeight(this.readerTextSize * this.readerLineHeight)
            .width('100%')
        } else {
          this.PagedText()
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.readerHorizontalPadding(), right: this.readerHorizontalPadding(),
      top: this.readerSafeTop(), bottom: 60 })
    .backgroundColor(this.readerBackground())
    .opacity(this.pageLayerOpacity(target))
    .translate({ x: this.pageLayerTranslation(target) })
  }

  @Builder
  private PagedReader() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.pageDragActive) {
        this.PagedLayer(true)
      }

      this.PagedLayer(false)

      Text(`${this.readerPageIndex + 1}/${Math.max(1, this.readerPages.length)}`)
        .fontSize(12)
        .fontColor(this.readerThemeMode === 3 ? '#9AA19D' : '#777D79')
        .position({ x: '82%', y: '94%' })
        .opacity(this.pageDragActive ? 0 : 1)
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
    .clip(true)
    .onAreaChange((oldArea: Area, area: Area): void => {
      const width = Number(area.width);
      const height = Number(area.height);
      if (width > 0 && height > 0 && (Math.abs(width - this.readerViewportWidth) > 1 ||
        Math.abs(height - this.readerViewportHeight) > 1)) {
        this.readerViewportWidth = width;
        this.readerViewportHeight = height;
        this.rebuildReaderPages();
      }
    })
    .onTouch((event: TouchEvent): void => {
      this.handlePagedTouch(event);
    })
  }

  @Builder
  private ReaderTopControls() {
    Row() {
      Text('‹')
        .fontSize(34)
        .fontColor('#F0ECE6')
        .width(48)
        .onClick(() => this.closeReader())
      Column() {
        Text(this.currentBookTitle())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F0ECE6')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.chapterIndex + 1} / ${this.chapters.length}`)
          .fontSize(11)
          .fontColor('#B8B3AD')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      Blank()
        .width(48)
    }
    .height(88)
    .width('100%')
    .padding({ left: 8, right: 8, top: 28 })
    .backgroundColor('#E61E1A19')
    .opacity(this.readerControlsProgress)
    .translate({ y: (this.readerControlsProgress - 1) * 88 })
    .position({ x: 0, y: 0 })
    .hitTestBehavior(this.readerControlsVisible ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private ReaderBottomControls() {
    Row() {
      Text('目录')
        .fontSize(15)
        .fontColor('#F0ECE6')
        .width('25%')
        .textAlign(TextAlign.Center)
        .onClick(() => this.openCatalog())
      Text(this.isCurrentBookmarked() ? '已书签' : '书签')
        .fontSize(15)
        .fontColor(this.isCurrentBookmarked() ? '#D8A64A' : '#F0ECE6')
        .width('25%')
        .textAlign(TextAlign.Center)
        .onClick(() => this.toggleBookmark())
      Text(this.readerReadMode === 0 ? '长按标记' : '长按笔记')
        .fontSize(13)
        .fontColor('#B8B3AD')
        .width('25%')
        .textAlign(TextAlign.Center)
      Text('设置')
        .fontSize(15)
        .fontColor('#F0ECE6')
        .width('25%')
        .textAlign(TextAlign.Center)
        .onClick(() => this.openSettings())
    }
    .height(64)
    .width('100%')
    .padding({ bottom: 10 })
    .backgroundColor('#E61E1A19')
    .border({ width: { top: 0.5 }, color: '#66807B76' })
    .opacity(this.readerControlsProgress)
    .translate({ y: (1 - this.readerControlsProgress) * 64 })
    .position({ x: 0, y: Math.max(0, this.readerViewportHeight - 64) })
    .hitTestBehavior(this.readerControlsVisible ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private ReaderPage() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.readerReadMode === 1) {
          Scroll(this.readerScroller) {
          Column() {
            Text(this.currentChapter().title)
              .fontSize(this.readerTextSize + 5)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.readerTextColor())
              .textAlign(TextAlign.Center)
              .width('100%')
              .margin({ top: this.readerSafeTop(), bottom: 32 })
              .onClick(() => this.toggleReaderControls())

            ForEach(this.paragraphs(), (paragraph: string, index: number) => {
              Text(undefined, { controller: this.paragraphTextController(index) }) {
                ForEach(this.readerTextSegments(`　　${paragraph}`, this.paragraphAbsoluteStart(index), this.chapterIndex),
                  (segment: ReaderTextSegment, segmentIndex: number) => {
                    if (segment.marked) {
                      Span(segment.text)
                        .decoration({ type: TextDecorationType.Underline, color: segment.color })
                    } else {
                      Span(segment.text)
                    }
                  }, (segment: ReaderTextSegment, segmentIndex: number): string =>
                    `${this.chapterIndex}_${index}_${segmentIndex}_${segment.text.length}`)
                if (this.notesAt(index).length > 0) {
                  Span(`  ◉ ${this.notesAt(index).length}`)
                    .fontColor('#C58A2D')
                    .fontWeight(FontWeight.Bold)
                }
              }
              .fontSize(this.readerTextSize)
              .fontColor(this.readerTextColor())
              .lineHeight(this.readerTextSize * this.readerLineHeight)
              .width('100%')
              .margin({ bottom: 15 })
              .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
              .copyOption(CopyOptions.LocalDevice)
              .bindSelectionMenu(TextSpanType.TEXT, this.ReaderSelectionMenu, TextResponseType.LONG_PRESS, {
                onAppear: (): void => this.showReaderSelectionMenu(),
                onDisappear: (): void => this.hideReaderSelectionMenu()
              })
              .onTextSelectionChange((selectionStart: number, selectionEnd: number): void => {
                this.updateReaderSelection(`　　${paragraph}`, this.paragraphAbsoluteStart(index),
                  this.paragraphTextController(index), selectionStart, selectionEnd);
              })
              .onClick((): void => {
                if (this.readerSelectionStart >= 0) {
                  this.closeReaderSelection();
                  return;
                }
                const notes = this.notesAt(index);
                if (notes.length > 0) {
                  this.openNoteEditor(index, notes[0]);
                } else {
                  this.toggleReaderControls();
                }
              })
            }, (paragraph: string, index: number) => `${this.chapterIndex}_${index}_${paragraph.length}`)

            Row() {
              Button('上一章')
                .enabled(this.chapterIndex > 0)
                .fontColor(this.readerTextColor())
                .backgroundColor('#00000000')
                .onClick(() => this.changeChapter(this.chapterIndex - 1))
              Blank()
              Button(this.chapterIndex + 1 >= this.chapters.length ? '已读完' : '下一章')
                .enabled(this.chapterIndex + 1 < this.chapters.length)
                .fontColor(this.readerTextColor())
                .backgroundColor('#00000000')
                .onClick(() => this.changeChapter(this.chapterIndex + 1))
            }
            .width('100%')
            .margin({ top: 24, bottom: 60 })
          }
          .width('100%')
          .padding({ left: this.readerHorizontalPadding(), right: this.readerHorizontalPadding() })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .onDidScroll(() => this.updateScrollOffset())
        .onScrollStop(() => {
          this.updateScrollOffset();
          this.persistProgress();
        })
        } else {
          this.PagedReader()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.readerBackground())
      .onAreaChange((oldArea: Area, area: Area): void => {
        const width = Number(area.width);
        const height = Number(area.height);
        if (width > 0 && height > 0 && (Math.abs(width - this.readerViewportWidth) > 1 ||
          Math.abs(height - this.readerViewportHeight) > 1)) {
          this.readerViewportWidth = width;
          this.readerViewportHeight = height;
          if (this.readerReadMode === 0) {
            this.rebuildReaderPages();
          }
        }
      })

      this.ReaderTopControls()
      this.ReaderBottomControls()

      if (this.showCatalog) {
        Row() {
          Column() {
            Row() {
              Text('目录')
                .fontSize(23)
                .fontWeight(FontWeight.Bold)
                .fontColor('#27312B')
              Blank()
              Text('×')
                .fontSize(28)
                .fontColor('#67726B')
                .onClick(() => this.closeCatalog())
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 24, bottom: 10 })

            Row() {
              ForEach([['bookmark', '书签'], ['catalog', '目录'], ['note', '笔记']], (tab: Array<string>) => {
                Column() {
                  Text(tab[1])
                    .fontSize(15)
                    .fontWeight(this.drawerTab === tab[0] ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.drawerTab === tab[0] ? '#365444' : '#737D76')
                  Blank()
                    .width(28)
                    .height(3)
                    .borderRadius(2)
                    .backgroundColor(this.drawerTab === tab[0] ? '#486555' : '#00000000')
                    .margin({ top: 8 })
                }
                .layoutWeight(1)
                .onClick(() => this.drawerTab = tab[0])
              }, (tab: Array<string>) => tab[0])
            }
            .height(52)
            .width('100%')
            .border({ width: { bottom: 0.5 }, color: '#DDE1DC' })

            if (this.drawerTab === 'catalog') {
              List() {
                ForEach(this.chapters, (chapter: ChapterRecord, index: number) => {
                  ListItem() {
                    Row() {
                      Text(`${index + 1}`)
                        .fontSize(13)
                        .fontColor(index === this.chapterIndex ? '#FFFFFF' : '#7B867F')
                        .textAlign(TextAlign.Center)
                        .width(30)
                        .height(30)
                        .borderRadius(15)
                        .backgroundColor(index === this.chapterIndex ? '#486454' : '#EDF0EC')
                      Text(chapter.title)
                        .fontSize(16)
                        .fontColor(index === this.chapterIndex ? '#365444' : '#313B35')
                        .fontWeight(index === this.chapterIndex ? FontWeight.Bold : FontWeight.Normal)
                        .maxLines(2)
                        .layoutWeight(1)
                        .margin({ left: 12 })
                    }
                    .width('100%')
                    .padding({ left: 18, right: 18, top: 13, bottom: 13 })
                    .onClick(() => this.changeChapter(index))
                  }
                }, (chapter: ChapterRecord, index: number) => `${index}_${chapter.title}`)
              }
              .layoutWeight(1)
            } else if (this.drawerTab === 'bookmark') {
              if (this.currentBookmarks().length === 0) {
                Text('还没有书签')
                  .fontSize(16)
                  .fontColor('#8A918C')
                  .margin({ top: 44 })
              } else {
                List() {
                  ForEach(this.currentBookmarks(), (bookmark: BookmarkRecord) => {
                    ListItem() {
                      Column() {
                        Text(bookmark.chapterTitle)
                          .fontSize(16)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#303A34')
                          .maxLines(1)
                          .width('100%')
                        Text(bookmark.summary)
                          .fontSize(13)
                          .fontColor('#727B75')
                          .maxLines(2)
                          .width('100%')
                          .margin({ top: 6 })
                      }
                      .width('100%')
                      .padding({ left: 18, right: 18, top: 14, bottom: 14 })
                      .onClick(() => this.openBookmark(bookmark))
                    }
                  }, (bookmark: BookmarkRecord) => bookmark.id)
                }
                .layoutWeight(1)
              }
            } else {
              if (this.currentNotes().length === 0) {
                Text('还没有笔记')
                  .fontSize(16)
                  .fontColor('#8A918C')
                  .margin({ top: 44 })
              } else {
                List() {
                  ForEach(this.currentNotes(), (note: NoteRecord) => {
                    ListItem() {
                      Column() {
                        Text(note.selectedText)
                          .fontSize(14)
                          .fontColor('#58615B')
                          .maxLines(2)
                          .width('100%')
                        Text(note.noteText)
                          .fontSize(16)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#303A34')
                          .maxLines(2)
                          .width('100%')
                          .margin({ top: 7 })
                      }
                      .width('100%')
                      .padding({ left: 18, right: 18, top: 14, bottom: 14 })
                      .onClick(() => this.openDrawerNote(note))
                    }
                  }, (note: NoteRecord) => note.id)
                }
                .layoutWeight(1)
              }
            }
          }
          .width('84%')
          .height('100%')
          .backgroundColor('#FAFBF8')
          .translate({ x: (this.catalogProgress - 1) * 360 })
          Blank()
            .layoutWeight(1)
            .height('100%')
            .backgroundColor('#66000000')
            .opacity(this.catalogScrimProgress)
            .onClick(() => this.closeCatalog())
        }
        .width('100%')
        .height('100%')
      }

      if (this.showSettings) {
        Scroll() {
        Column() {
          Row() {
            Text('阅读设置')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#252D28')
            Blank()
            Text('完成')
              .fontSize(16)
              .fontColor('#416550')
              .onClick(() => this.closeSettings())
          }
          .width('100%')

          Row() {
            Text('翻页')
              .fontSize(14)
              .fontColor(this.readerReadMode === 0 ? '#FFFFFF' : '#445047')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(40)
              .borderRadius(20)
              .backgroundColor(this.readerReadMode === 0 ? '#486555' : '#EEF1ED')
              .margin({ right: 8 })
              .onClick((): void => {
                this.setReaderReadMode(0);
              })
            Text('滚动')
              .fontSize(14)
              .fontColor(this.readerReadMode === 1 ? '#FFFFFF' : '#445047')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(40)
              .borderRadius(20)
              .backgroundColor(this.readerReadMode === 1 ? '#486555' : '#EEF1ED')
              .onClick((): void => {
                this.setReaderReadMode(1);
              })
          }
          .width('100%')
          .margin({ top: 18 })

          Text(`字号  ${Math.round(this.readerTextSize)}`)
            .fontSize(14)
            .fontColor('#687169')
            .width('100%')
            .margin({ top: 22 })
          Slider({ value: this.readerTextSize, min: 14, max: 32, step: 1 })
            .selectedColor('#486555')
            .onChange((value: number) => {
              this.readerTextSize = value;
              if (this.readerReadMode === 0) {
                this.rebuildReaderPages();
              }
            })

          Text(`行距  ${this.readerLineHeight.toFixed(1)}`)
            .fontSize(14)
            .fontColor('#687169')
            .width('100%')
            .margin({ top: 12 })
          Slider({ value: this.readerLineHeight, min: 1.2, max: 2.2, step: 0.1 })
            .selectedColor('#486555')
            .onChange((value: number) => {
              this.readerLineHeight = value;
              if (this.readerReadMode === 0) {
                this.rebuildReaderPages();
              }
            })

          Text(`页边距  ${Math.round(this.readerPageMargin)}`)
            .fontSize(14)
            .fontColor('#687169')
            .width('100%')
            .margin({ top: 12 })
          Slider({ value: this.readerPageMargin, min: 12, max: 40, step: 2 })
            .selectedColor('#486555')
            .onChange((value: number) => {
              this.readerPageMargin = value;
              if (this.readerReadMode === 0) {
                this.rebuildReaderPages();
              }
            })

          Row() {
            ForEach(['默认', '纸张', '护眼', '夜间'], (label: string, index: number) => {
              Text(label)
                .fontSize(14)
                .fontColor(this.readerThemeMode === index ? '#FFFFFF' : '#445047')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .backgroundColor(this.readerThemeMode === index ? '#486555' : '#EEF1ED')
                .margin({ right: index < 3 ? 8 : 0 })
                .onClick(() => {
                  animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
                    this.readerThemeMode = index;
                  });
                })
            })
          }
          .width('100%')
          .margin({ top: 20, bottom: 10 })
        }
        .width('100%')
        .padding({ left: 22, right: 22, top: 20, bottom: 24 })
        }
        .width('100%')
        .height(this.readerSettingsPanelHeight())
        .scrollBar(BarState.Off)
        .backgroundColor('#FFFFFF')
        .borderRadius({ topLeft: 22, topRight: 22 })
        .position({ x: 0, y: this.readerSettingsPanelTop() })
        .shadow({ radius: 22, color: '#33000000', offsetY: -4 })
        .opacity(this.settingsProgress)
        .translate({ y: (1 - this.settingsProgress) * 360 })
      }

      if (this.noteEditorVisible) {
        Column() {
          Row() {
            Text(this.editingNoteId.length === 0 ? '写笔记' : '编辑笔记')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#27312B')
            Blank()
            Text('取消')
              .fontSize(15)
              .fontColor('#737D76')
              .onClick(() => this.closeNoteEditor())
          }
          .width('100%')
          Text(this.noteParagraphIndex >= 0 && this.noteParagraphIndex < this.paragraphs().length ?
            this.paragraphs()[this.noteParagraphIndex] : '')
            .fontSize(14)
            .fontColor('#6C756F')
            .maxLines(3)
            .width('100%')
            .margin({ top: 14, bottom: 12 })
          TextArea({ text: this.noteDraft, placeholder: '记录你的想法…' })
            .maxLength(2000)
            .fontSize(16)
            .height(120)
            .backgroundColor('#F3F5F1')
            .borderRadius(12)
            .onChange((value: string) => this.noteDraft = value)
          Row() {
            if (this.editingNoteId.length > 0) {
              Button('删除')
                .fontColor('#B74434')
                .backgroundColor('#F8ECE9')
                .onClick(() => this.deleteEditingNote())
            }
            Blank()
            Button('保存')
              .fontColor('#FFFFFF')
              .backgroundColor('#486555')
              .enabled(this.noteDraft.trim().length > 0)
              .onClick(() => this.saveNote())
          }
          .width('100%')
          .margin({ top: 16 })
        }
        .width('100%')
        .padding({ left: 22, right: 22, top: 20, bottom: 24 })
        .backgroundColor('#FFFFFF')
        .borderRadius({ topLeft: 22, topRight: 22 })
        .position({ x: 0, y: '42%' })
        .shadow({ radius: 24, color: '#44000000', offsetY: -4 })
        .opacity(this.noteProgress)
        .translate({ y: (1 - this.noteProgress) * 420 })
      }
    }
    .width('100%')
    .height('100%')
    .opacity(this.readerProgress)
    .scale({ x: 0.985 + this.readerProgress * 0.015, y: 0.985 + this.readerProgress * 0.015 })
  }

  build() {
    if (this.page === 'reader') {
      this.ReaderPage();
    } else {
      this.ShelfPage();
    }
  }
}
