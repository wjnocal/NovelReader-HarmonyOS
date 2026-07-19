import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate<boolean>('appInForeground', true);
    AppStorage.setOrCreate<string>('onlineDownloadStatus', 'idle');
    AppStorage.setOrCreate<string>('onlineDownloadMessage', '');
    AppStorage.setOrCreate<number>('onlineDownloadCompleted', 0);
    AppStorage.setOrCreate<number>('onlineDownloadTotal', 0);
    AppStorage.setOrCreate<string>('onlineDownloadTitle', '');
    AppStorage.setOrCreate<number>('onlineDownloadUpdatedAt', 0);
    AppStorage.setOrCreate<string>('onlineDownloadBookId', '');
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true);
      // Keep the gesture/navigation area available, but hide the top status bar on every page.
      mainWindow.setWindowSystemBarEnable(['navigation']);
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
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    AppStorage.setOrCreate<boolean>('appInForeground', true);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    AppStorage.setOrCreate<boolean>('appInForeground', false);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
