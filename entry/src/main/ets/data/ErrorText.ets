import { BusinessError } from '@kit.BasicServicesKit';

export class ErrorText {
  static from(error: BusinessError): string {
    const message = error.message === undefined ? '' : error.message.trim();
    const code = error.code === undefined ? 0 : error.code;
    if (message.length > 0) {
      return code > 0 && message.indexOf(`${code}`) < 0 ? `${message}（错误码 ${code}）` : message;
    }
    let detail = '';
    try {
      detail = JSON.stringify(error);
    } catch (jsonError) {
      detail = '';
    }
    if (detail.length > 0 && detail !== '{}') {
      return detail;
    }
    if (code > 0) {
      return `未知错误（错误码 ${code}）`;
    }
    return '未知错误';
  }
}
