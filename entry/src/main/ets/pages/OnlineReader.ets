import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { LibraryStore } from '../data/LibraryStore';
import { OnlineBookService } from '../data/OnlineBookService';
import { OnlinePageContent, OnlinePageExtractor } from '../data/OnlinePageExtractor';
import { OnlineExtractionRule } from '../model/Models';

class OnlineReaderParams {
  initialUrl: string = '';
}

@Entry
@Component
struct OnlineReader {
  @State private webSrc: string = 'about:blank';
  @State private currentUrl: string = '';
  @State private bookTitle: string = '在线阅读';
  @State private chapterTitle: string = '';
  @State private content: string = '';
  @State private previousUrl: string = '';
  @State private nextUrl: string = '';
  @State private previousSitePageUrl: string = '';
  @State private nextSitePageUrl: string = '';
  @State private sourceName: string = '通用网页';
  @State private statusText: string = '正在打开网页…';
  @State private loading: boolean = true;
  @State private settingsVisible: boolean = false;
  @State private textSize: number = 19;
  @State private lineHeight: number = 1.65;
  @State private themeMode: number = 0;
  @State private pageMargin: number = 22;
  @State private readMode: number = 1;
  @State private pages: Array<string> = new Array<string>();
  @State private pageIndex: number = 0;
  @State private pendingDirection: number = 0;
  @State private controlsVisible: boolean = false;
  @State private controlsProgress: number = 0;
  @State private viewportWidth: number = 360;
  @State private viewportHeight: number = 720;
  private controller: webview.WebviewController = new webview.WebviewController();
  private service: OnlineBookService | undefined = undefined;
  private extractionTicket: number = 0;
  private touchTracking: boolean = false;
  private touchMoved: boolean = false;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private touchCurrentX: number = 0;
  private touchCurrentY: number = 0;
  private touchStartedAt: number = 0;
  private pendingLoadKind: string = 'initial';
  private continuationStartPage: number = 0;
  private visitedSitePages: Set<string> = new Set<string>();

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.service = new OnlineBookService(context);
    const snapshot = LibraryStore.load(context);
    this.textSize = snapshot.settings.textSize;
    this.lineHeight = snapshot.settings.lineHeight;
    this.themeMode = snapshot.settings.themeMode;
    this.pageMargin = snapshot.settings.pageMargin;
    this.readMode = snapshot.settings.readMode === 0 ? 0 : 1;
    const params = this.getUIContext().getRouter().getParams() as OnlineReaderParams;
    this.webSrc = params === undefined ? 'about:blank' : params.initialUrl;
    this.currentUrl = this.webSrc;
  }

  aboutToDisappear(): void {
    this.saveSettings();
  }

  onBackPress(): boolean {
    if (this.settingsVisible) {
      this.settingsVisible = false;
      this.saveSettings();
      return true;
    }
    return false;
  }

  private toggleControls(): void {
    this.setControlsVisible(!this.controlsVisible);
  }

  private setControlsVisible(visible: boolean): void {
    if (this.settingsVisible && visible) {
      return;
    }
    if (this.controlsVisible === visible && this.controlsProgress === (visible ? 1 : 0)) {
      return;
    }
    this.controlsVisible = visible;
    animateTo({ duration: visible ? 220 : 160, curve: visible ? Curve.EaseOut : Curve.EaseIn }, (): void => {
      this.controlsProgress = visible ? 1 : 0;
    });
  }

  private openSettings(): void {
    this.settingsVisible = true;
    this.setControlsVisible(false);
  }

  private closeSettings(): void {
    this.saveSettings();
    this.settingsVisible = false;
  }

  private touchX(event: TouchEvent): number {
    if (event.touches.length > 0) return event.touches[0].x;
    if (event.changedTouches.length > 0) return event.changedTouches[0].x;
    return this.touchCurrentX;
  }

  private touchY(event: TouchEvent): number {
    if (event.touches.length > 0) return event.touches[0].y;
    if (event.changedTouches.length > 0) return event.changedTouches[0].y;
    return this.touchCurrentY;
  }

  private handleReaderTouch(event: TouchEvent): void {
    const x = this.touchX(event);
    const y = this.touchY(event);
    if (event.type === TouchType.Down) {
      this.touchTracking = true;
      this.touchMoved = false;
      this.touchStartX = x;
      this.touchStartY = y;
      this.touchCurrentX = x;
      this.touchCurrentY = y;
      this.touchStartedAt = Date.now();
      return;
    }
    if (!this.touchTracking) return;
    this.touchCurrentX = x;
    this.touchCurrentY = y;
    if (event.type === TouchType.Move) {
      const dx = x - this.touchStartX;
      const dy = y - this.touchStartY;
      if (Math.abs(dx) > 16 || Math.abs(dy) > 16) {
        this.touchMoved = true;
      }
      return;
    }
    if (event.type === TouchType.Up) {
      const dx = x - this.touchStartX;
      const dy = y - this.touchStartY;
      const heldFor = Date.now() - this.touchStartedAt;
      const moved = this.touchMoved;
      this.touchTracking = false;
      this.touchMoved = false;
      if (this.readMode === 0 && moved && Math.abs(dx) > 44 && Math.abs(dx) > Math.abs(dy)) {
        if (dx < 0) this.nextPage(); else this.previousPage();
        return;
      }
      if (!moved && heldFor < 450) {
        const width = Math.max(1, this.viewportWidth);
        if (this.readMode === 0 && x < width / 3) {
          this.previousPage();
        } else if (this.readMode === 0 && x > width * 2 / 3) {
          this.nextPage();
        } else if (x >= width / 3 && x <= width * 2 / 3) {
          this.toggleControls();
        }
      }
      return;
    }
    if (event.type === TouchType.Cancel) {
      this.touchTracking = false;
      this.touchMoved = false;
    }
  }

  private saveSettings(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const snapshot = LibraryStore.load(context);
    snapshot.settings.textSize = this.textSize;
    snapshot.settings.lineHeight = this.lineHeight;
    snapshot.settings.themeMode = this.themeMode;
    snapshot.settings.pageMargin = this.pageMargin;
    snapshot.settings.readMode = this.readMode;
    snapshot.settingsUpdatedAt = Date.now();
    LibraryStore.save(context, snapshot);
  }

  private readerBackground(): string {
    switch (this.themeMode) {
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
    return this.themeMode === 3 ? '#D7D9D7' : '#282A27';
  }

  private secondaryTextColor(): string {
    return this.themeMode === 3 ? '#A7ABA8' : '#687169';
  }

  private barBackground(): string {
    return this.themeMode === 3 ? '#F0242826' : '#F7F4ED';
  }

  private readerSafeTop(): number {
    return Math.max(56, Math.round(this.textSize * this.lineHeight + this.pageMargin + 12));
  }

  private horizontalPadding(): number {
    const centeredPadding = Math.max(0, (this.viewportWidth - 760) / 2);
    return Math.max(this.pageMargin, centeredPadding);
  }

  private settingsPanelHeight(): number {
    if (this.viewportWidth > this.viewportHeight) {
      return Math.min(360, Math.max(240, this.viewportHeight - 24));
    }
    return Math.min(390, Math.max(300, this.viewportHeight * 0.42));
  }

  private scheduleExtraction(url: string): void {
    const ticket = ++this.extractionTicket;
    setTimeout((): void => {
      if (ticket === this.extractionTicket) {
        this.extractPage(url, ticket);
      }
    }, 450);
  }

  private async extractPage(url: string, ticket: number): Promise<void> {
    try {
      const rule: OnlineExtractionRule = await this.service!.getExtractionRule(url);
      if (ticket !== this.extractionTicket) {
        return;
      }
      this.sourceName = rule.sourceName;
      this.statusText = rule.sourceId.length > 0 ? `正在使用 ${rule.sourceName} 规则提取正文…` : '正在识别网页正文…';
      const raw = await this.controller.runJavaScript(OnlinePageExtractor.buildScript(rule));
      if (ticket !== this.extractionTicket) {
        return;
      }
      const page: OnlinePageContent = OnlinePageExtractor.parse(raw);
      if (page.error.length > 0) {
        throw new Error(page.error);
      }
      if (page.content.trim().length < 40) {
        throw new Error('没有识别到足够的正文，请在浏览器中打开具体章节页面后重试');
      }
      this.currentUrl = page.url.length > 0 ? page.url : url;
      this.visitedSitePages.add(this.currentUrl);
      if (this.pendingLoadKind === 'append') {
        const addition = page.content.trim();
        if (addition.length > 0 && this.content.indexOf(addition) < 0) {
          this.content = `${this.content.trim()}\n\n${addition}`;
        }
        if (page.nextChapterUrl.length > 0) this.nextUrl = page.nextChapterUrl;
        if (page.previousChapterUrl.length > 0 && this.previousUrl.length === 0) {
          this.previousUrl = page.previousChapterUrl;
        }
        this.previousSitePageUrl = '';
        this.nextSitePageUrl = this.visitedSitePages.has(page.nextPageUrl) ? '' : page.nextPageUrl;
        this.rebuildPages();
        this.pageIndex = Math.min(Math.max(0, this.continuationStartPage), this.pages.length - 1);
      } else {
        this.bookTitle = page.bookTitle.length > 0 ? page.bookTitle : '在线阅读';
        this.chapterTitle = page.title.length > 0 ? page.title : this.bookTitle;
        this.content = page.content;
        this.previousSitePageUrl = this.visitedSitePages.has(page.previousPageUrl) ? '' : page.previousPageUrl;
        this.nextSitePageUrl = this.visitedSitePages.has(page.nextPageUrl) ? '' : page.nextPageUrl;
        this.previousUrl = page.previousChapterUrl.length > 0 ? page.previousChapterUrl :
          (page.previousPageUrl.length === 0 ? page.previousUrl : '');
        this.nextUrl = page.nextChapterUrl.length > 0 ? page.nextChapterUrl :
          (page.nextPageUrl.length === 0 ? page.nextUrl : '');
        this.rebuildPages();
        if (this.pendingDirection < 0 && this.pages.length > 0) {
          this.pageIndex = this.pages.length - 1;
        } else {
          this.pageIndex = 0;
        }
      }
      this.pendingDirection = 0;
      this.pendingLoadKind = '';
      this.loading = false;
      this.controlsVisible = false;
      this.controlsProgress = 0;
      this.statusText = `${this.sourceName} · 网页模式不保存书签和阅读进度`;
    } catch (error) {
      if (ticket !== this.extractionTicket) {
        return;
      }
      this.loading = false;
      this.statusText = `提取失败：${String(error)}`;
    }
  }

  private rebuildPages(): void {
    const usableWidth = Math.max(180, this.viewportWidth - this.horizontalPadding() * 2);
    const output = new Array<string>();
    const paragraphs = this.content.split(/\n+/).map((value: string): string => value.trim())
      .filter((value: string): boolean => value.length > 0);
    const fullText = paragraphs.map((paragraph: string): string => `　　${paragraph}`).join('\n\n');
    let offset = 0;
    while (offset < fullText.length && output.length < 10000) {
      const remaining = fullText.substring(offset);
      const firstPage = output.length === 0;
      let low = 1;
      let high = remaining.length;
      let best = 1;
      while (low <= high) {
        const middle = Math.floor((low + high) / 2);
        if (this.pageTextFits(remaining.substring(0, middle), usableWidth, firstPage)) {
          best = middle;
          low = middle + 1;
        } else {
          high = middle - 1;
        }
      }
      let end = Math.max(1, best);
      if (end < remaining.length) {
        const minimumBreak = Math.floor(end * 0.72);
        const paragraphBreak = remaining.lastIndexOf('\n\n', end);
        if (paragraphBreak >= minimumBreak) {
          end = paragraphBreak;
        } else {
          for (let index = end; index >= minimumBreak; index--) {
            if ('。！？；，.!?;'.indexOf(remaining.charAt(index - 1)) >= 0) {
              end = index;
              break;
            }
          }
        }
      }
      const page = remaining.substring(0, end).trim();
      if (page.length > 0) output.push(page);
      offset += end;
      while (offset < fullText.length && /\s/.test(fullText.charAt(offset))) offset++;
    }
    this.pages = output.length > 0 ? output : [this.content];
    this.pageIndex = Math.min(this.pageIndex, this.pages.length - 1);
  }

  private pageTextFits(text: string, usableWidth: number, firstPage: boolean): boolean {
    const pageIndicatorHeight = 28;
    let availableHeight = this.viewportHeight - this.readerSafeTop() - 46 - pageIndicatorHeight - 12;
    if (firstPage) {
      try {
        const titleSize = this.getUIContext().getMeasureUtils().measureTextSize({
          textContent: this.chapterTitle,
          constraintWidth: `${usableWidth}vp`,
          fontSize: `${this.textSize + 5}fp`,
          fontWeight: FontWeight.Bold
        });
        availableHeight -= this.getUIContext().px2vp(Number(titleSize.height)) + 28;
      } catch (error) {
        availableHeight -= (this.textSize + 5) * 1.4 + 28;
      }
    }
    availableHeight = Math.max(this.textSize * this.lineHeight * 3, availableHeight);
    try {
      const measured = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: text,
        constraintWidth: `${usableWidth}vp`,
        fontSize: `${this.textSize}fp`,
        lineHeight: `${this.textSize * this.lineHeight}vp`
      });
      return Number(measured.height) <= this.getUIContext().vp2px(availableHeight);
    } catch (error) {
      const charactersPerLine = Math.max(6, Math.floor(usableWidth / (this.textSize * 1.15)));
      const lines = Math.max(3, Math.floor(availableHeight / (this.textSize * this.lineHeight)) - 2);
      return text.length <= charactersPerLine * lines;
    }
  }

  private loadChapter(url: string, direction: number): void {
    if (url.length === 0 || this.loading) {
      return;
    }
    this.pendingDirection = direction;
    this.pendingLoadKind = 'chapter';
    this.visitedSitePages.clear();
    this.loading = true;
    this.statusText = direction < 0 ? '正在加载上一章…' : '正在加载下一章…';
    this.controller.loadUrl(url);
  }

  private loadSitePage(url: string, append: boolean): void {
    if (url.length === 0 || this.loading || this.visitedSitePages.has(url)) return;
    if (!append) this.visitedSitePages.clear();
    this.pendingDirection = append ? 1 : -1;
    this.pendingLoadKind = append ? 'append' : 'page';
    this.continuationStartPage = this.pages.length;
    this.loading = true;
    this.statusText = append ? '正在加载本章下一页…' : '正在加载本章上一页…';
    this.controller.loadUrl(url);
  }

  private previousPage(): void {
    this.setControlsVisible(false);
    if (this.readMode === 0 && this.pageIndex > 0) {
      this.pageIndex--;
      return;
    }
    if (this.previousSitePageUrl.length > 0) {
      this.loadSitePage(this.previousSitePageUrl, false);
      return;
    }
    this.loadChapter(this.previousUrl, -1);
  }

  private nextPage(): void {
    this.setControlsVisible(false);
    if (this.readMode === 0 && this.pageIndex + 1 < this.pages.length) {
      this.pageIndex++;
      return;
    }
    if (this.nextSitePageUrl.length > 0) {
      this.loadSitePage(this.nextSitePageUrl, true);
      return;
    }
    this.loadChapter(this.nextUrl, 1);
  }

  private setReadMode(mode: number): void {
    this.readMode = mode === 0 ? 0 : 1;
    if (this.readMode === 0) {
      this.rebuildPages();
    }
  }

  @Builder
  private ReaderBody() {
    if (this.loading && this.content.length === 0) {
      Column({ space: 18 }) {
        LoadingProgress()
          .width(42)
          .height(42)
          .color('#567562')
        Text(this.statusText)
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.content.length === 0) {
      Column({ space: 16 }) {
        Text('未能进入阅读模式')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.readerTextColor())
        Text(this.statusText)
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
          .textAlign(TextAlign.Center)
          .padding({ left: 28, right: 28 })
        Button('返回浏览器')
          .fontColor('#FFFFFF')
          .backgroundColor('#476A58')
          .onClick((): void => this.getUIContext().getRouter().back())
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.readMode === 1) {
      Scroll() {
        Column() {
          Text(this.chapterTitle)
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.readerTextColor())
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: this.readerSafeTop(), bottom: 32 })
          ForEach(this.content.split(/\n+/).filter((value: string): boolean => value.trim().length > 0),
            (paragraph: string, index: number) => {
              Text(`　　${paragraph.trim()}`)
                .fontSize(this.textSize)
                .fontColor(this.readerTextColor())
                .lineHeight(this.textSize * this.lineHeight)
                .width('100%')
                .margin({ bottom: 12 })
                .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
                .copyOption(CopyOptions.LocalDevice)
            }, (paragraph: string, index: number): string => `${index}_${paragraph.length}`)
          Row() {
            Button(this.previousSitePageUrl.length > 0 ? '上一页' :
              (this.previousUrl.length > 0 ? '上一章' : '没有上一章'))
              .enabled((this.previousSitePageUrl.length > 0 || this.previousUrl.length > 0) && !this.loading)
              .fontColor(this.readerTextColor())
              .backgroundColor(Color.Transparent)
              .onClick((): void => this.previousPage())
            Blank()
            Button(this.nextSitePageUrl.length > 0 ? '下一页' :
              (this.nextUrl.length > 0 ? '下一章' : '已读到当前末尾'))
              .enabled((this.nextSitePageUrl.length > 0 || this.nextUrl.length > 0) && !this.loading)
              .fontColor(this.readerTextColor())
              .backgroundColor(Color.Transparent)
              .onClick((): void => this.nextPage())
          }
          .width('100%')
          .margin({ top: 22, bottom: 38 })
        }
        .width('100%')
        .padding({ left: this.horizontalPadding(), right: this.horizontalPadding() })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .onDidScroll((): void => this.setControlsVisible(false))
      .onTouch((event: TouchEvent): void => this.handleReaderTouch(event))
    } else {
      Column() {
        if (this.pageIndex === 0) {
          Text(this.chapterTitle)
            .fontSize(this.textSize + 5)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.readerTextColor())
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ bottom: 28 })
        }
        Text(this.pages.length > 0 ? this.pages[this.pageIndex] : this.content)
          .fontSize(this.textSize)
          .fontColor(this.readerTextColor())
          .lineHeight(this.textSize * this.lineHeight)
          .width('100%')
          .layoutWeight(1)
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
          .copyOption(CopyOptions.LocalDevice)
        Text(`${this.pageIndex + 1}/${Math.max(1, this.pages.length)}`)
          .fontSize(12)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.End)
          .margin({ bottom: 8 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.horizontalPadding(), right: this.horizontalPadding(),
        top: this.readerSafeTop(), bottom: 46 })
      .onTouch((event: TouchEvent): void => this.handleReaderTouch(event))
    }
  }

  @Builder
  private SettingsPanel() {
    if (this.settingsVisible) {
      Column() {
        Blank()
          .width('100%')
          .layoutWeight(1)
          .onClick((): void => {
            this.closeSettings();
          })
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
              .onClick((): void => this.closeSettings())
          }
          .width('100%')
          Row() {
            Text('翻页')
              .fontSize(14)
              .fontColor(this.readMode === 0 ? '#FFFFFF' : '#445047')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(40)
              .borderRadius(20)
              .backgroundColor(this.readMode === 0 ? '#486555' : '#EEF1ED')
              .margin({ right: 8 })
              .onClick((): void => this.setReadMode(0))
            Text('滚动')
              .fontSize(14)
              .fontColor(this.readMode === 1 ? '#FFFFFF' : '#445047')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(40)
              .borderRadius(20)
              .backgroundColor(this.readMode === 1 ? '#486555' : '#EEF1ED')
              .onClick((): void => this.setReadMode(1))
          }
          .width('100%')
          .margin({ top: 18 })
          Text(`字号  ${Math.round(this.textSize)}`)
            .fontSize(14)
            .fontColor('#687169')
            .width('100%')
            .margin({ top: 22 })
          Slider({ value: this.textSize, min: 14, max: 32, step: 1 })
            .selectedColor('#486555')
            .onChange((value: number): void => {
              this.textSize = value;
              if (this.readMode === 0) this.rebuildPages();
            })
          Text(`行距  ${this.lineHeight.toFixed(1)}`)
            .fontSize(14)
            .fontColor('#687169')
            .width('100%')
            .margin({ top: 12 })
          Slider({ value: this.lineHeight, min: 1.2, max: 2.2, step: 0.1 })
            .selectedColor('#486555')
            .onChange((value: number): void => {
              this.lineHeight = value;
              if (this.readMode === 0) this.rebuildPages();
            })
          Text(`页边距  ${Math.round(this.pageMargin)}`)
            .fontSize(14)
            .fontColor('#687169')
            .width('100%')
            .margin({ top: 12 })
          Slider({ value: this.pageMargin, min: 12, max: 40, step: 2 })
            .selectedColor('#486555')
            .onChange((value: number): void => {
              this.pageMargin = value;
              if (this.readMode === 0) this.rebuildPages();
            })
          Row() {
            ForEach(['默认', '纸张', '护眼', '夜间'], (label: string, index: number) => {
              Text(label)
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontColor(this.themeMode === index ? '#FFFFFF' : '#445047')
                .textAlign(TextAlign.Center)
                .borderRadius(20)
                .backgroundColor(this.themeMode === index ? '#486555' : '#EEF1ED')
                .margin({ right: index < 3 ? 8 : 0 })
                .onClick((): void => { this.themeMode = index; })
            })
          }
          .width('100%')
          .margin({ top: 20, bottom: 10 })
          Text('在线阅读不会保存书签、笔记和进度，下载到书架后可使用完整本地阅读功能。')
            .fontSize(12)
            .fontColor('#7B8780')
            .width('100%')
        }
        .width('100%')
        .padding({ left: 22, right: 22, top: 20, bottom: 24 })
        }
        .width('100%')
        .height(this.settingsPanelHeight())
        .scrollBar(BarState.Off)
        .backgroundColor('#FFFFFF')
        .borderRadius({ topLeft: 22, topRight: 22 })
        .shadow({ radius: 22, color: '#33000000', offsetY: -4 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#22000000')
    }
  }

  @Builder
  private ReaderTopControls() {
    Row() {
      Text('‹')
        .fontSize(34)
        .fontColor('#F0ECE6')
        .width(48)
        .height(48)
        .textAlign(TextAlign.Center)
        .onClick((): void => this.getUIContext().getRouter().back())
      Column() {
        Text(this.bookTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F0ECE6')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.sourceName} · 在线阅读`)
          .fontSize(11)
          .fontColor('#B8B3AD')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      Blank().width(48)
    }
    .height(88)
    .width('100%')
    .padding({ left: 8, right: 8, top: 28 })
    .backgroundColor('#E61E1A19')
    .opacity(this.controlsProgress)
    .translate({ y: (this.controlsProgress - 1) * 88 })
    .position({ x: 0, y: 0 })
    .hitTestBehavior(this.controlsVisible ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private ReaderBottomControls() {
    Row() {
      Text(this.readMode === 0 && this.pageIndex > 0 ? '上一页' :
        (this.previousSitePageUrl.length > 0 ? '上一页' : '上一章'))
        .fontSize(15)
        .fontColor((this.pageIndex > 0 || this.previousSitePageUrl.length > 0 || this.previousUrl.length > 0) ?
          '#F0ECE6' : '#77736F')
        .width('25%')
        .height(54)
        .textAlign(TextAlign.Center)
        .onClick((): void => this.previousPage())
      Text('网页模式')
        .fontSize(13)
        .fontColor('#D8A64A')
        .width('25%')
        .height(54)
        .textAlign(TextAlign.Center)
      Text(this.readMode === 0 && this.pageIndex + 1 < this.pages.length ? '下一页' :
        (this.nextSitePageUrl.length > 0 ? '下一页' : '下一章'))
        .fontSize(15)
        .fontColor((this.pageIndex + 1 < this.pages.length || this.nextSitePageUrl.length > 0 ||
          this.nextUrl.length > 0) ? '#F0ECE6' : '#77736F')
        .width('25%')
        .height(54)
        .textAlign(TextAlign.Center)
        .onClick((): void => this.nextPage())
      Text('设置')
        .fontSize(15)
        .fontColor('#F0ECE6')
        .width('25%')
        .height(54)
        .textAlign(TextAlign.Center)
        .onClick((): void => this.openSettings())
    }
    .height(64)
    .width('100%')
    .padding({ bottom: 10 })
    .backgroundColor('#E61E1A19')
    .border({ width: { top: 0.5 }, color: '#66807B76' })
    .opacity(this.controlsProgress)
    .translate({ y: (1 - this.controlsProgress) * 64 })
    .position({ x: 0, y: Math.max(0, this.viewportHeight - 64) })
    .hitTestBehavior(this.controlsVisible ? HitTestMode.Default : HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.ReaderBody()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.readerBackground())
      .onAreaChange((oldArea: Area, area: Area): void => {
        const width = Number(area.width);
        const height = Number(area.height);
        if (width > 0 && height > 0 && (Math.abs(width - this.viewportWidth) > 1 ||
          Math.abs(height - this.viewportHeight) > 1)) {
          this.viewportWidth = width;
          this.viewportHeight = height;
          if (this.readMode === 0) this.rebuildPages();
        }
      })

      Web({ src: this.webSrc, controller: this.controller })
        .width(1)
        .height(1)
        .opacity(0.01)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .mixedMode(MixedMode.Compatible)
        .userAgent('Mozilla/5.0 (Linux; HarmonyOS; Mobile) AppleWebKit/537.36 Chrome/114.0 Mobile Safari/537.36 NovelReader/OnlineReader')
        .onPageBegin((event: OnPageBeginEvent): void => {
          this.currentUrl = event.url;
          this.loading = true;
        })
        .onPageEnd((event: OnPageEndEvent): void => {
          this.currentUrl = event.url;
          this.scheduleExtraction(event.url);
        })

      this.ReaderTopControls()
      this.ReaderBottomControls()

      this.SettingsPanel()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.readerBackground())
    .safeAreaPadding({ top: 8, bottom: 8 })
  }
}
