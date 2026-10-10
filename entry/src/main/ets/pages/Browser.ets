import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';

class BrowserParams {
  initialUrl: string = '';
}

@Entry
@Component
struct Browser {
  @State private webSrc: string = 'https://www.bing.com/search?q=%E5%B0%8F%E8%AF%B4';
  @State private currentUrl: string = '';
  @State private address: string = '';
  @State private pageTitle: string = '内置浏览器';
  @State private progress: number = 0;
  @State private canGoBack: boolean = false;
  @State private canGoForward: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as BrowserParams;
    const initial = params === undefined ? '' : params.initialUrl;
    this.webSrc = this.normalizeAddress(initial);
    this.currentUrl = this.webSrc;
    this.address = this.webSrc;
  }

  onBackPress(): boolean {
    if (this.safeCanGoBack()) {
      this.controller.backward();
      return true;
    }
    return false;
  }

  private normalizeAddress(value: string): string {
    const clean = (value ?? '').trim();
    if (clean.length === 0) {
      return 'https://www.bing.com/search?q=%E5%B0%8F%E8%AF%B4';
    }
    const lower = clean.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return clean;
    }
    if (clean.indexOf('.') >= 0 && clean.indexOf(' ') < 0) {
      return `https://${clean}`;
    }
    return `https://www.bing.com/search?q=${encodeURIComponent(clean)}`;
  }

  private loadAddress(): void {
    const target = this.normalizeAddress(this.address);
    this.address = target;
    this.controller.loadUrl(target);
  }

  private safeCanGoBack(): boolean {
    try {
      return this.controller.accessBackward();
    } catch (error) {
      return false;
    }
  }

  private safeCanGoForward(): boolean {
    try {
      return this.controller.accessForward();
    } catch (error) {
      return false;
    }
  }

  private updateNavigation(): void {
    this.canGoBack = this.safeCanGoBack();
    this.canGoForward = this.safeCanGoForward();
  }

  private openExternal(url: string): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.startAbility({ action: 'ohos.want.action.viewData', uri: url }).catch((): void => {
      promptAction.showToast({ message: '无法打开这个链接' });
    });
  }

  private openOnlineReader(): void {
    if (!this.currentUrl.toLowerCase().startsWith('http://') &&
      !this.currentUrl.toLowerCase().startsWith('https://')) {
      promptAction.showToast({ message: '当前页面不能进入在线阅读' });
      return;
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/OnlineReader',
      params: { initialUrl: this.currentUrl }
    });
  }

  build() {
    Column() {
      Column({ space: 7 }) {
        Row() {
          Text(this.pageTitle)
            .fontSize(13)
            .fontColor($r('app.color.ui_text_secondary'))
            .maxLines(1)
            .layoutWeight(1)
          Text('网页阅读 · 不保存浏览记录')
            .fontSize(11)
            .fontColor($r('app.color.ui_text_muted'))
        }
        .width('100%')

        Row({ space: 5 }) {
          Text('‹')
            .width(42)
            .height(42)
            .fontSize(28)
            .fontColor($r('app.color.ui_text_primary'))
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.ui_surface_button'))
            .borderRadius(10)
            .onClick((): void => {
              if (this.safeCanGoBack()) {
                this.controller.backward();
              } else {
                this.getUIContext().getRouter().back();
              }
            })
          Text('›')
            .width(42)
            .height(42)
            .fontSize(28)
            .fontColor(this.canGoForward ? $r('app.color.ui_text_primary') : $r('app.color.ui_text_muted'))
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.ui_surface_button'))
            .borderRadius(10)
            .onClick((): void => {
              if (this.safeCanGoForward()) {
                this.controller.forward();
              }
            })
          Text('刷新')
            .width(48)
            .height(42)
            .fontSize(13)
            .fontColor($r('app.color.ui_text_primary'))
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.ui_surface_button'))
            .borderRadius(10)
            .onClick((): void => this.controller.refresh())
          TextInput({ text: this.address, placeholder: '输入网址或搜索小说' })
            .height(40)
            .layoutWeight(1)
            .fontSize(13)
            .fontColor($r('app.color.ui_text_primary'))
            .placeholderColor($r('app.color.ui_text_muted'))
            .caretColor($r('app.color.ui_text_accent'))
            .backgroundColor($r('app.color.ui_surface'))
            .border({ width: 1, color: $r('app.color.ui_border') })
            .borderRadius(10)
            .enterKeyType(EnterKeyType.Go)
            .onChange((value: string): void => { this.address = value; })
            .onSubmit((): void => this.loadAddress())
          Text('前往')
            .width(56)
            .height(42)
            .fontSize(13)
            .fontColor($r('app.color.ui_text_on_accent'))
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.ui_browser_accent'))
            .borderRadius(10)
            .onClick((): void => this.loadAddress())
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.ui_page_background'))

      if (this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color('#4E735F')
      }

      Stack({ alignContent: Alignment.BottomEnd }) {
        Web({ src: this.webSrc, controller: this.controller })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .darkMode(WebDarkMode.Auto)
          .forceDarkAccess(true)
          .domStorageAccess(true)
          .databaseAccess(true)
          .mixedMode(MixedMode.Compatible)
          .userAgent('Mozilla/5.0 (Linux; HarmonyOS; Mobile) AppleWebKit/537.36 Chrome/114.0 Mobile Safari/537.36 NovelReader/OnlineBrowser')
          .onPageBegin((event: OnPageBeginEvent): void => {
            this.currentUrl = event.url;
            this.address = event.url;
            this.progress = 1;
            this.updateNavigation();
          })
          .onPageEnd((event: OnPageEndEvent): void => {
            this.currentUrl = event.url;
            this.address = event.url;
            this.progress = 100;
            this.updateNavigation();
          })
          .onProgressChange((event: OnProgressChangeEvent): void => {
            this.progress = event.newProgress;
          })
          .onTitleReceive((event: OnTitleReceiveEvent): void => {
            this.pageTitle = event.title.length > 0 ? event.title : '内置浏览器';
          })
          .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
            const url = request.getRequestUrl();
            const lower = url.toLowerCase();
            if (lower.startsWith('http://') || lower.startsWith('https://')) {
              return false;
            }
            this.openExternal(url);
            return true;
          })

        Text('在线\n阅读')
          .width(72)
          .height(72)
          .fontSize(14)
          .lineHeight(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ui_text_on_accent'))
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.ui_browser_accent'))
          .borderRadius(36)
          .shadow({ radius: 12, color: '#55000000', offsetY: 4 })
          .margin({ right: 18, bottom: 22 })
          .onClick((): void => this.openOnlineReader())
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ui_page_background'))
    .safeAreaPadding({ top: 8, bottom: 8 })
  }
}
