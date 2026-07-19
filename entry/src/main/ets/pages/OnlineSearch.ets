import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { OnlineDownloadManager } from '../data/OnlineDownloadManager';
import { OnlineBookService } from '../data/OnlineBookService';
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
  @StorageLink('onlineDownloadStatus') private downloadStatus: string = 'idle';
  @StorageLink('onlineDownloadMessage') private downloadMessage: string = '';
  @StorageLink('onlineDownloadCompleted') private downloadCompleted: number = 0;
  @StorageLink('onlineDownloadTotal') private downloadTotal: number = 0;
  @StorageLink('onlineDownloadTitle') private downloadTitle: string = '';
  @StorageLink('onlineDownloadUpdatedAt') private downloadUpdatedAt: number = 0;
  private service: OnlineBookService | undefined = undefined;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.service = new OnlineBookService(context);
    this.loadSources();
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
    this.groups = new Array<OnlineBookGroup>();
    this.statusText = '准备搜索…';
    try {
      const results = await this.service!.searchSelected(value, this.selectedSourceIds,
        (message: string): void => { this.statusText = message; });
      this.groups = OnlineSearchGrouper.group(results, value);
      this.statusText = `找到 ${this.groups.length} 本书，共 ${results.length} 个书源结果`;
    } catch (error) {
      this.statusText = String(error);
    } finally {
      this.busy = false;
    }
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

  @Builder
  private ModeSegment(label: string, value: string) {
    Button(label)
      .height(38)
      .layoutWeight(1)
      .fontSize(14)
      .fontWeight(this.mode === value ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.mode === value ? '#FFFFFF' : '#42534B')
      .backgroundColor(this.mode === value ? '#476A58' : '#EDF2EE')
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
      .fontColor(this.format === value ? '#FFFFFF' : '#42534B')
      .backgroundColor(this.format === value ? '#476A58' : '#EDF2EE')
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
            .fontColor(this.downloadStatus === 'failed' ? '#A13C3C' : '#315443')
          Blank()
          if (this.downloadStatus === 'running') {
            Button('取消')
              .height(30)
              .fontSize(13)
              .backgroundColor('#E8EEE9')
              .fontColor('#42534B')
              .onClick((): void => OnlineDownloadManager.shared().cancel())
          }
        }
        .width('100%')
        Text(this.downloadMessage)
          .fontSize(13)
          .fontColor('#637169')
          .width('100%')
          .maxLines(2)
        if (this.downloadStatus === 'running' && this.downloadTotal > 0) {
          Progress({ value: this.downloadCompleted, total: this.downloadTotal, type: ProgressType.Linear })
            .width('100%')
            .color('#4E735F')
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#F2F7F3')
      .borderRadius(14)
      .margin({ top: 12 })
    }
  }

  @Builder
  private ResultCard(group: OnlineBookGroup, index: number) {
    Column({ space: 7 }) {
      Row() {
        Text(group.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#25362E')
          .layoutWeight(1)
          .maxLines(1)
        Text(`${group.versions.length} 个书源`)
          .fontSize(12)
          .fontColor('#4E735F')
          .backgroundColor('#E8F1EB')
          .borderRadius(9)
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
      }
      .width('100%')
      if (group.author.length > 0) {
        Text(group.author)
          .fontSize(13)
          .fontColor('#65716B')
          .width('100%')
      }
      Text(group.versions.map((item: OnlineBookResult): string => item.sourceName).join(' · '))
        .fontSize(12)
        .fontColor('#8A948F')
        .width('100%')
        .maxLines(1)
    }
    .width('100%')
    .padding(15)
    .backgroundColor('#FFFFFF')
    .borderRadius(14)
    .onClick((): void => { this.selectedGroupIndex = index; })
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
                .fontColor('#24372E')
              Text(`选择下载书源 · ${this.format.toUpperCase()}`)
                .fontSize(13)
                .fontColor('#6B7770')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Button('关闭')
              .height(34)
              .fontSize(13)
              .backgroundColor('#EDF1EE')
              .fontColor('#44534B')
              .onClick((): void => { this.selectedGroupIndex = -1; })
          }
          .width('100%')
          ForEach(this.groups[this.selectedGroupIndex].versions, (result: OnlineBookResult) => {
            Button(`${result.sourceName}${result.author.length > 0 ? ` · ${result.author}` : ''}`)
              .width('100%')
              .height(48)
              .fontSize(15)
              .fontColor('#FFFFFF')
              .backgroundColor('#476A58')
              .borderRadius(12)
              .onClick((): void => this.beginDownload(result))
          }, (result: OnlineBookResult): string => `${result.sourceId}_${result.url}`)
        }
        .width('100%')
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius({ topLeft: 24, topRight: 24 })
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
            .fontColor('#2E4338')
            .backgroundColor(Color.Transparent)
            .onClick((): void => this.getUIContext().getRouter().back())
          Text('在线搜书')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#24372E')
          Blank()
          Button('浏览器')
            .height(34)
            .fontSize(13)
            .fontColor('#FFFFFF')
            .backgroundColor('#476A58')
            .margin({ right: 8 })
            .onClick((): void => this.openBrowser())
          Text(`${this.selectedSourceIds.length}/${this.sources.length}`)
            .fontSize(13)
            .fontColor('#637169')
        }
        .width('100%')
        .height(54)
        .padding({ right: 16 })
        .backgroundColor('#F7FAF7')

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
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .onChange((value: string): void => { this.query = value; })

            Row() {
              Text('使用书源')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor('#2C4035')
              Blank()
              Button('全选')
                .height(32)
                .fontSize(13)
                .backgroundColor('#E8EFEA')
                .fontColor('#496354')
                .onClick((): void => this.selectAllSearchable())
              Button('清空')
                .height(32)
                .fontSize(13)
                .backgroundColor('#E8EFEA')
                .fontColor('#496354')
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
                      .fontColor(source.enabled ? '#354A3F' : '#9AA39E')
                    Text(`并发 ${source.concurrency}${source.comment.length > 0 ? ` · ${source.comment}` : ''}`)
                      .fontSize(11)
                      .fontColor('#8B958F')
                      .maxLines(1)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Button('打开')
                    .height(30)
                    .fontSize(12)
                    .fontColor('#496354')
                    .backgroundColor('#E8EFEA')
                    .onClick((): void => this.openBrowser(source.baseUrl))
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
              }, (source: OnlineSourceInfo): string => source.id)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .backgroundColor('#FFFFFF')
            .borderRadius(14)

            Button(this.busy ? '搜索中…' : this.mode === 'keyword' ? '开始搜索' : `使用 ${this.format.toUpperCase()} 下载`)
              .width('100%')
              .height(50)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor('#476A58')
              .enabled(!this.busy)
              .onClick((): void => { this.submit(); })
            Text(this.statusText)
              .width('100%')
              .fontSize(13)
              .fontColor('#68766F')
            this.DownloadCard()

            ForEach(this.groups, (group: OnlineBookGroup, index: number) => {
              this.ResultCard(group, index)
            }, (group: OnlineBookGroup): string => group.title)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 28 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .backgroundColor('#F4F6F3')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F7FAF7')
      .safeAreaPadding({ top: 8, bottom: 8 })

      this.SourceDialog()
    }
    .width('100%')
    .height('100%')
  }
}
