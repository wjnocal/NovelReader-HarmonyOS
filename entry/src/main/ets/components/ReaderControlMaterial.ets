import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

// Guard API 26 at runtime so the existing API 23 minimum remains supported.
export class ReaderControlMaterial {
  private material: uiMaterial.ImmersiveMaterial | undefined = undefined;

  constructor(interactive: boolean) {
    if (deviceInfo.sdkApiVersion < 26) return;
    try {
      if (uiMaterial.isImmersiveMaterialSupported() &&
        uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE) {
        this.material = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          colorInvert: true,
          interactive: interactive,
          lightEffect: interactive ? {} : null
        });
      }
    } catch (error) {
      console.warn(`Cannot initialize reader system material: ${String(error)}`);
    }
  }

  getMaterial(): uiMaterial.ImmersiveMaterial | undefined {
    return this.material;
  }
}
