import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate<boolean>('appInForeground', true);
    AppStorage.setOrCreate<string>('onlineDownloadStatus', 'idle');
    AppStorage.setOrCreate<string>('onlineDownloadMessage', '');
    AppStorage.setOrCreate<number>('onlineDownloadCompleted', 0);
    AppStorage.setOrCreate<number>('onlineDownloadTotal', 0);
    AppStorage.setOrCreate<string>('onlineDownloadTitle', '');
    AppStorage.setOrCreate<number>('onlineDownloadUpdatedAt', 0);
    AppStorage.setOrCreate<string>('onlineDownloadBookId', '');
    AppStorage.setOrCreate<number>('onlineLibraryRevision', 0);
    AppStorage.setOrCreate<string>('openLocalBookId', '');
    this.handleReaderWant(want);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    this.updateColorMode(this.context.config);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.updateColorMode(newConfig);
  }

  private updateColorMode(config: Configuration): void {
    if (config.colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_DARK &&
      config.colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) return;
    const dark = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate<boolean>('systemDarkMode', dark);
    if (this.mainWindow === undefined) return;
    try {
      this.mainWindow.setWindowBackgroundColor(dark ? '#000000' : '#F7F4F1');
      this.mainWindow.setWindowSystemBarProperties({
        navigationBarColor: dark ? '#000000' : '#F7F4F1',
        navigationBarContentColor: dark ? '#FFFFFF' : '#111111'
      }).catch((err: Error): void => {
        hilog.error(DOMAIN, 'testTag', 'Failed to update navigation colors: %{public}s', String(err));
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to update window colors: %{public}s', String(err));
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleReaderWant(want);
  }

  private handleReaderWant(want: Want): void {
    const id = want.parameters?.openBookId;
    if (typeof id === 'string' && id.length > 0) AppStorage.setOrCreate<string>('openLocalBookId', id);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    try {
      const mainWindow = windowStage.getMainWindowSync();
      this.mainWindow = mainWindow;
      mainWindow.setWindowLayoutFullScreen(true);
      // Keep the gesture/navigation area available, but hide the top status bar on every page.
      mainWindow.setWindowSystemBarEnable(['navigation']);
      this.updateColorMode(this.context.config);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to enter immersive mode. Cause: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    this.mainWindow = undefined;
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    AppStorage.setOrCreate<boolean>('appInForeground', true);
    this.updateColorMode(this.context.config);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    AppStorage.setOrCreate<boolean>('appInForeground', false);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
