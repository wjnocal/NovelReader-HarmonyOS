import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { OnlineDownloadManager } from '../data/OnlineDownloadManager';
import { OnlineBookService, OnlineDownloadCancelToken } from '../data/OnlineBookService';
import { OnlineSearchGrouper } from '../data/OnlineSearchGrouper';
import { OnlineBookGroup, OnlineBookResult, OnlineSourceInfo } from '../model/Models';

@Entry
@Component
struct OnlineSearch {
  @State private mode: string = 'keyword';
  @State private format: string = 'txt';
  @State private query: string = '';
  @State private sources: Array<OnlineSourceInfo> = new Array<OnlineSourceInfo>();
  @State private selectedSourceIds: Array<string> = new Array<string>();
  @State private groups: Array<OnlineBookGroup> = new Array<OnlineBookGroup>();
  @State private busy: boolean = false;
  @State private statusText: string = '选择书源后搜索，多个书源的同名结果会自动合并';
  @State private selectedGroupIndex: number = -1;
  @State private viewportHeight: number = 720;
  @StorageLink('onlineDownloadStatus') private downloadStatus: string = 'idle';
  @StorageLink('onlineDownloadMessage') private downloadMessage: string = '';
  @StorageLink('onlineDownloadCompleted') private downloadCompleted: number = 0;
  @StorageLink('onlineDownloadTotal') private downloadTotal: number = 0;
  @StorageLink('onlineDownloadTitle') private downloadTitle: string = '';
  @StorageLink('onlineDownloadUpdatedAt') private downloadUpdatedAt: number = 0;
  @StorageLink('onlineDownloadBookId') private readableBookId: string = '';
  private service: OnlineBookService | undefined = undefined;
  private searchToken: OnlineDownloadCancelToken | undefined = undefined;
  private searchTicket: number = 0;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.service = new OnlineBookService(context);
    this.loadSources();
  }

  aboutToDisappear(): void {
    this.stopSearch();
  }

  private stopSearch(): void {
    if (!this.busy) return;
    this.searchTicket++;
    this.searchToken?.cancel();
    this.searchToken = undefined;
    this.busy = false;
    this.statusText = this.groups.length > 0 ? `已停止搜索，保留 ${this.groups.length} 本书的结果` : '已停止搜索，可重新搜索';
  }

  private async loadSources(): Promise<void> {
    try {
      this.sources = await this.service!.getSources();
      this.selectedSourceIds = this.sources.filter((source: OnlineSourceInfo): boolean => source.enabled)
        .map((source: OnlineSourceInfo): string => source.id);
    } catch (error) {
      this.statusText = `读取书源失败：${String(error)}`;
    }
  }

  private toggleSource(id: string, selected: boolean): void {
    const values = this.selectedSourceIds.slice();
    const index = values.indexOf(id);
    if (selected && index < 0) {
      values.push(id);
    } else if (!selected && index >= 0) {
      values.splice(index, 1);
    }
    this.selectedSourceIds = values;
  }

  private async submit(): Promise<void> {
    if (this.busy) return;
    const value = this.query.trim();
    if (value.length === 0) {
      promptAction.showToast({ message: this.mode === 'keyword' ? '请输入书名或作者' : '请输入书籍详情页网址' });
      return;
    }
    if (this.selectedSourceIds.length === 0) {
      promptAction.showToast({ message: '请至少选择一个书源' });
      return;
    }
    if (this.mode === 'url') {
      try {
        const result = await this.service!.resultForUrl(value, this.selectedSourceIds);
        this.beginDownload(result);
      } catch (error) {
        this.statusText = String(error);
      }
      return;
    }
    this.busy = true;
    const ticket = ++this.searchTicket;
    const token = new OnlineDownloadCancelToken('搜索已取消');
    this.searchToken = token;
    this.groups = new Array<OnlineBookGroup>();
    this.statusText = '准备搜索…';
    try {
      const results = await this.service!.searchSelected(value, this.selectedSourceIds,
        (message: string): void => {
          if (ticket === this.searchTicket) this.statusText = message;
        }, token, (results: Array<OnlineBookResult>): void => {
          if (ticket !== this.searchTicket) return;
          this.updateSearchResults(results, value);
        });
      if (ticket !== this.searchTicket) return;
      this.updateSearchResults(results, value);
    } catch (error) {
      if (ticket === this.searchTicket) this.statusText = String(error);
    } finally {
      if (ticket === this.searchTicket) {
        this.busy = false;
        this.searchToken = undefined;
      }
    }
  }

  private updateSearchResults(results: Array<OnlineBookResult>, keyword: string): void {
    const selected = this.groups[this.selectedGroupIndex];
    this.groups = OnlineSearchGrouper.group(results, keyword);
    this.selectedGroupIndex = selected === undefined ? -1 :
      this.groups.findIndex((group: OnlineBookGroup): boolean =>
        group.title === selected.title && group.author === selected.author);
  }

  private beginDownload(result: OnlineBookResult): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const started = OnlineDownloadManager.shared().start(context, result, this.format);
    if (!started) {
      promptAction.showToast({ message: '已有一本书正在下载，请稍候' });
      return;
    }
    this.selectedGroupIndex = -1;
    promptAction.showToast({ message: '已开始后台下载，可返回书架继续使用应用' });
  }

  private selectAllSearchable(): void {
    this.selectedSourceIds = this.sources.filter((source: OnlineSourceInfo): boolean =>
      source.enabled && (this.mode === 'url' || source.searchable)).map((source: OnlineSourceInfo): string => source.id);
  }

  private openBrowser(initialUrl: string = ''): void {
    const value = initialUrl.length > 0 ? initialUrl : this.query.trim();
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/Browser',
      params: { initialUrl: value }
    });
  }

  private readDownloadingBook(): void {
    if (this.readableBookId.length === 0) return;
    AppStorage.setOrCreate<string>('openLocalBookId', this.readableBookId);
    this.getUIContext().getRouter().back();
  }

  @Builder
  private ModeSegment(label: string, value: string) {
    Button(label)
      .height(38)
      .layoutWeight(1)
      .fontSize(14)
      .fontWeight(this.mode === value ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.mode === value ? $r('app.color.ui_text_on_accent') : $r('app.color.ui_text_primary'))
      .backgroundColor(this.mode === value ? $r('app.color.ui_browser_accent') : $r('app.color.ui_surface_button'))
      .borderRadius(10)
      .scale({ x: this.mode === value ? 1 : 0.98, y: this.mode === value ? 1 : 0.98 })
      .animation({ duration: 160, curve: Curve.EaseOut })
      .onClick((): void => {
        if (this.mode !== value) {
          this.mode = value;
        }
      })
  }

  @Builder
  private FormatSegment(label: string, value: string) {
    Button(label)
      .height(38)
      .layoutWeight(1)
      .fontSize(14)
      .fontWeight(this.format === value ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.format === value ? $r('app.color.ui_text_on_accent') : $r('app.color.ui_text_primary'))
      .backgroundColor(this.format === value ? $r('app.color.ui_browser_accent') : $r('app.color.ui_surface_button'))
      .borderRadius(10)
      .scale({ x: this.format === value ? 1 : 0.98, y: this.format === value ? 1 : 0.98 })
      .animation({ duration: 160, curve: Curve.EaseOut })
      .onClick((): void => {
        if (this.format !== value) {
          this.format = value;
        }
      })
  }

  @Builder
  private DownloadCard() {
    if (this.downloadStatus === 'running' || this.downloadStatus === 'completed' ||
      this.downloadStatus === 'failed' || this.downloadStatus === 'cancelled') {
      Column({ space: 8 }) {
        Row() {
          Text(this.downloadStatus === 'running' ? '后台下载中' :
            this.downloadStatus === 'completed' ? '下载完成' :
              this.downloadStatus === 'cancelled' ? '下载已取消' : '下载失败')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.downloadStatus === 'failed' ? $r('app.color.ui_text_error') : $r('app.color.ui_text_accent'))
          Blank()
          if (this.downloadStatus === 'running') {
            Button('取消')
              .height(30)
              .fontSize(13)
              .backgroundColor($r('app.color.ui_surface_button'))
              .fontColor($r('app.color.ui_text_primary'))
              .onClick((): void => OnlineDownloadManager.shared().cancel())
          }
        }
        .width('100%')
        Text(this.downloadMessage)
          .fontSize(13)
          .fontColor($r('app.color.ui_text_secondary'))
          .width('100%')
          .maxLines(2)
        if (this.downloadStatus === 'running' && this.downloadTotal > 0) {
          Progress({ value: this.downloadCompleted, total: this.downloadTotal, type: ProgressType.Linear })
            .width('100%')
            .color('#4E735F')
        }
        if (this.readableBookId.length > 0) {
          Button(this.downloadStatus === 'running' ? '立即阅读（后续章节继续下载）' : '阅读已下载章节')
            .width('100%')
            .height(42)
            .fontSize(14)
            .backgroundColor($r('app.color.ui_browser_accent'))
            .fontColor($r('app.color.ui_text_on_accent'))
            .onClick((): void => this.readDownloadingBook())
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.ui_surface_success'))
      .borderRadius(14)
      .margin({ top: 12 })
    }
  }

  @Builder
  private ResultCard(group: OnlineBookGroup) {
    Column({ space: 7 }) {
      Row() {
        Text(group.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ui_text_primary'))
          .layoutWeight(1)
          .maxLines(1)
        Text(`${group.versions.length} 个书源`)
          .fontSize(12)
          .fontColor($r('app.color.ui_text_accent'))
          .backgroundColor($r('app.color.ui_surface_success'))
          .borderRadius(9)
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
      }
      .width('100%')
      if (group.author.length > 0) {
        Text(group.author)
          .fontSize(13)
          .fontColor($r('app.color.ui_text_secondary'))
          .width('100%')
      }
      Text(group.versions.map((item: OnlineBookResult): string => item.sourceName).join(' · '))
        .fontSize(12)
        .fontColor($r('app.color.ui_text_muted'))
        .width('100%')
        .maxLines(1)
    }
    .width('100%')
    .padding(15)
    .backgroundColor($r('app.color.ui_surface'))
    .borderRadius(14)
    .onClick((): void => {
      this.selectedGroupIndex = this.groups.findIndex((item: OnlineBookGroup): boolean =>
        item.title === group.title && item.author === group.author);
    })
  }

  @Builder
  private SourceDialog() {
    if (this.selectedGroupIndex >= 0 && this.selectedGroupIndex < this.groups.length) {
      Column() {
        Blank()
        Column({ space: 10 }) {
          Row() {
            Column({ space: 3 }) {
              Text(this.groups[this.selectedGroupIndex].title)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.ui_text_primary'))
              Text(`选择下载书源 · ${this.format.toUpperCase()}`)
                .fontSize(13)
                .fontColor($r('app.color.ui_text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Button('关闭')
              .height(34)
              .fontSize(13)
              .backgroundColor($r('app.color.ui_surface_button'))
              .fontColor($r('app.color.ui_text_primary'))
              .onClick((): void => { this.selectedGroupIndex = -1; })
          }
          .width('100%')
          Scroll() {
            Column({ space: 10 }) {
          ForEach(this.groups[this.selectedGroupIndex].versions, (result: OnlineBookResult) => {
            Button(`${result.sourceName}${result.author.length > 0 ? ` · ${result.author}` : ''}`)
              .width('100%')
              .height(48)
              .fontSize(15)
              .fontColor($r('app.color.ui_text_on_accent'))
              .backgroundColor($r('app.color.ui_browser_accent'))
              .borderRadius(12)
              .onClick((): void => this.beginDownload(result))
          }, (result: OnlineBookResult): string => `${result.sourceId}_${result.url}`)
            }
            .width('100%')
          }
          .height(Math.min(this.groups[this.selectedGroupIndex].versions.length * 58,
            Math.max(100, this.viewportHeight * 0.65)))
          .scrollBar(BarState.Auto)
        }
        .width('100%')
        .padding(20)
        .backgroundColor($r('app.color.ui_surface'))
        .borderRadius({ topLeft: 24, topRight: 24 })
        .constraintSize({ maxHeight: '85%' })
        .safeAreaPadding({ bottom: 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#66000000')
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Button('‹')
            .width(42)
            .height(42)
            .fontSize(30)
            .fontColor($r('app.color.ui_text_primary'))
            .backgroundColor(Color.Transparent)
            .onClick((): void => this.getUIContext().getRouter().back())
          Text('在线搜书')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ui_text_primary'))
          Blank()
          Button('浏览器')
            .height(34)
            .fontSize(13)
            .fontColor($r('app.color.ui_text_on_accent'))
            .backgroundColor($r('app.color.ui_browser_accent'))
            .margin({ right: 8 })
            .onClick((): void => this.openBrowser())
          Text(`${this.selectedSourceIds.length}/${this.sources.length}`)
            .fontSize(13)
            .fontColor($r('app.color.ui_text_secondary'))
        }
        .width('100%')
        .height(54)
        .padding({ right: 16 })
        .backgroundColor($r('app.color.ui_page_background'))

        Scroll() {
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              this.ModeSegment('书名搜索', 'keyword')
              this.ModeSegment('网址下载', 'url')
            }
            .width('100%')
            Row({ space: 8 }) {
              this.FormatSegment('TXT', 'txt')
              this.FormatSegment('EPUB', 'epub')
            }
            .width('100%')
            TextInput({
              text: this.query,
              placeholder: this.mode === 'keyword' ? '输入书名或作者' : '粘贴书籍详情页 URL'
            })
              .width('100%')
              .height(50)
              .fontColor($r('app.color.ui_text_primary'))
              .placeholderColor($r('app.color.ui_text_muted'))
              .caretColor($r('app.color.ui_text_accent'))
              .backgroundColor($r('app.color.ui_surface'))
              .borderRadius(12)
              .onChange((value: string): void => { this.query = value; })

            Row() {
              Text('使用书源')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.ui_text_primary'))
              Blank()
              Button('全选')
                .height(32)
                .fontSize(13)
                .backgroundColor($r('app.color.ui_surface_button'))
                .fontColor($r('app.color.ui_text_accent'))
                .onClick((): void => this.selectAllSearchable())
              Button('清空')
                .height(32)
                .fontSize(13)
                .backgroundColor($r('app.color.ui_surface_button'))
                .fontColor($r('app.color.ui_text_accent'))
                .margin({ left: 6 })
                .onClick((): void => { this.selectedSourceIds = new Array<string>(); })
            }
            .width('100%')

            Column() {
              ForEach(this.sources, (source: OnlineSourceInfo) => {
                Row({ space: 8 }) {
                  Checkbox({ name: source.id, group: 'onlineSources' })
                    .select(this.selectedSourceIds.indexOf(source.id) >= 0)
                    .enabled(source.enabled && (this.mode === 'url' || source.searchable))
                    .selectedColor('#476A58')
                    .onChange((selected: boolean): void => this.toggleSource(source.id, selected))
                  Column({ space: 2 }) {
                    Text(`${source.name}${source.needProxy ? ' · 需代理' : ''}${!source.searchable ? ' · 仅网址' : ''}`)
                      .fontSize(14)
                      .fontColor(source.enabled ? $r('app.color.ui_text_primary') : $r('app.color.ui_text_muted'))
                    Text(`并发 ${source.concurrency}${source.comment.length > 0 ? ` · ${source.comment}` : ''}`)
                      .fontSize(11)
                      .fontColor($r('app.color.ui_text_muted'))
                      .maxLines(1)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Button('打开')
                    .height(30)
                    .fontSize(12)
                    .fontColor($r('app.color.ui_text_accent'))
                    .backgroundColor($r('app.color.ui_surface_button'))
                    .enabled(source.enabled)
                    .onClick((): void => this.openBrowser(source.baseUrl))
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
              }, (source: OnlineSourceInfo): string => source.id)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .backgroundColor($r('app.color.ui_surface'))
            .borderRadius(14)

            Button(this.busy ? '停止搜索' : this.mode === 'keyword' ? '开始搜索' : `使用 ${this.format.toUpperCase()} 下载`)
              .width('100%')
              .height(50)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ui_text_on_accent'))
              .backgroundColor($r('app.color.ui_browser_accent'))
              .onClick((): void => {
                if (this.busy) this.stopSearch();
                else this.submit();
              })
            Text(this.statusText)
              .width('100%')
              .fontSize(13)
              .fontColor($r('app.color.ui_text_secondary'))
            this.DownloadCard()

            ForEach(this.groups, (group: OnlineBookGroup) => {
              this.ResultCard(group)
            }, (group: OnlineBookGroup): string => JSON.stringify([group.title, group.author]) +
              JSON.stringify(group.versions.map((result: OnlineBookResult): string => `${result.sourceId}|${result.url}`)))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 28 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .backgroundColor($r('app.color.ui_page_background'))
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.ui_page_background'))
      .safeAreaPadding({ top: 8, bottom: 8 })

      this.SourceDialog()
    }
    .width('100%')
    .height('100%')
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions): void => {
      this.viewportHeight = Number(newSize.height);
    })
  }
}
