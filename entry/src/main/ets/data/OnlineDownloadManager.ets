import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BookRecord, OnlineBookResult } from '../model/Models';
import { OnlineBookService, OnlineDownloadCancelToken } from './OnlineBookService';

export class OnlineDownloadManager {
  private static instance: OnlineDownloadManager = new OnlineDownloadManager();
  private running: boolean = false;
  private token: OnlineDownloadCancelToken | undefined = undefined;
  private lastProgressAt: number = 0;
  private notificationBookId: string = '';

  static shared(): OnlineDownloadManager {
    return OnlineDownloadManager.instance;
  }

  isRunning(): boolean {
    return this.running;
  }

  start(context: common.UIAbilityContext, result: OnlineBookResult, format: string): boolean {
    if (this.running) {
      return false;
    }
    this.running = true;
    this.token = new OnlineDownloadCancelToken();
    AppStorage.setOrCreate<string>('onlineDownloadBookId', '');
    this.lastProgressAt = 0;
    this.notificationBookId = '';
    this.publish('running', `准备从 ${result.sourceName} 下载《${result.bookName}》`, 0, 0, result.bookName);
    this.run(context, result, format, this.token);
    return true;
  }

  cancel(): void {
    this.token?.cancel();
    if (this.running) {
      this.publish('running', '正在取消下载…', 0, 0, this.currentTitle());
    }
  }

  isDownloading(bookId: string): boolean {
    return this.running && (AppStorage.get<string>('onlineDownloadBookId') ?? '') === bookId;
  }

  private async run(context: common.UIAbilityContext, result: OnlineBookResult, format: string,
    token: OnlineDownloadCancelToken): Promise<void> {
    let backgroundStarted = false;
    try {
      backgroundStarted = await this.startContinuousTask(context);
      const service = new OnlineBookService(context);
      const book = await service.downloadToLibrary(result, format,
        (message: string, completed?: number, total?: number): void => {
          if (Date.now() - this.lastProgressAt < 250 && completed !== total) return;
          this.lastProgressAt = Date.now();
          this.publish('running', message, completed ?? 0, total ?? 0, result.bookName);
        }, token, (book: BookRecord): void => {
          AppStorage.setOrCreate<string>('onlineDownloadBookId', book.id);
          if (backgroundStarted && this.notificationBookId !== book.id) {
            this.notificationBookId = book.id;
            this.updateNotificationTarget(context, book.id);
          }
        });
      this.publish('completed', `《${book.title}》下载完成，已加入书架`, book.totalChapters,
        book.totalChapters, book.title, book);
    } catch (error) {
      const message = String(error);
      const status = token.cancelled ? 'cancelled' : 'failed';
      const retained = (AppStorage.get<string>('onlineDownloadBookId') ?? '').length > 0 ?
        '；已下载章节保留在书架，选择原书源和格式可继续下载' : '';
      this.publish(status, `${token.cancelled ? '下载已取消' : `下载失败：${message}`}${retained}`,
        AppStorage.get<number>('onlineDownloadCompleted') ?? 0,
        AppStorage.get<number>('onlineDownloadTotal') ?? 0, result.bookName);
    } finally {
      this.running = false;
      this.token = undefined;
      if (backgroundStarted) {
        try {
          await backgroundTaskManager.stopBackgroundRunning(context);
        } catch (error) {
          // The system may already have stopped the task notification.
        }
      }
    }
  }

  private async startContinuousTask(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const agent = await wantAgent.getWantAgent({
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 1001,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      if (agent === null) {
        return false;
      }
      await backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      return true;
    } catch (error) {
      AppStorage.setOrCreate<string>('onlineDownloadBackgroundNotice',
        '系统未授予持续任务权限，下载将在应用前台继续');
      return false;
    }
  }

  private async updateNotificationTarget(context: common.UIAbilityContext, bookId: string): Promise<void> {
    try {
      await wantAgent.getWantAgent({
        wants: [{ bundleName: context.abilityInfo.bundleName, abilityName: context.abilityInfo.name,
          parameters: { openBookId: bookId } }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 1001,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
    } catch (error) {
      // The bookshelf and download card remain available if the system cannot update this target.
    }
  }

  private publish(status: string, message: string, completed: number, total: number, title: string,
    book?: BookRecord): void {
    AppStorage.setOrCreate<string>('onlineDownloadStatus', status);
    AppStorage.setOrCreate<string>('onlineDownloadMessage', message);
    AppStorage.setOrCreate<number>('onlineDownloadCompleted', completed);
    AppStorage.setOrCreate<number>('onlineDownloadTotal', total);
    AppStorage.setOrCreate<string>('onlineDownloadTitle', title);
    AppStorage.setOrCreate<number>('onlineDownloadUpdatedAt', Date.now());
    if (book !== undefined) {
      AppStorage.setOrCreate<string>('onlineDownloadBookId', book.id);
    }
  }

  private currentTitle(): string {
    return AppStorage.get<string>('onlineDownloadTitle') ?? '';
  }
}
