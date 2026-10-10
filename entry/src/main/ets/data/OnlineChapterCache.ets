import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { LibraryStore } from './LibraryStore';
import { OnlineDownloadState } from './OnlineDownloadState';

class CacheMetadata {
  identity: string = '';
  sha256: string = '';
  updatedAt: number = 0;
}

class CacheFile {
  path: string = '';
  size: number = 0;
  modified: number = 0;
}

export class OnlineChapterCache {
  private root: string;

  constructor(context: common.UIAbilityContext) {
    this.root = `${context.cacheDir}/online_chapters`;
    LibraryStore.ensureDirectory(this.root);
  }

  async read(identity: string): Promise<string> {
    const path = `${this.root}/${OnlineDownloadState.key(identity)}`;
    try {
      const metadata = JSON.parse(fs.readTextSync(`${path}.json`)) as CacheMetadata;
      if (metadata.identity !== identity || Date.now() - metadata.updatedAt > 7 * 86400000 ||
        await hash.hash(`${path}.txt`, 'sha256') !== metadata.sha256) return '';
      return fs.readTextSync(`${path}.txt`);
    } catch (error) {
      return '';
    }
  }

  async write(identity: string, content: string): Promise<void> {
    if (content.trim().length === 0) return;
    const path = `${this.root}/${OnlineDownloadState.key(identity)}`;
    const metadata = new CacheMetadata();
    metadata.identity = identity;
    metadata.updatedAt = Date.now();
    LibraryStore.writeAtomic(`${path}.txt`, content);
    metadata.sha256 = await hash.hash(`${path}.txt`, 'sha256');
    LibraryStore.writeAtomic(`${path}.json`, JSON.stringify(metadata));
  }

  prune(): void {
    const files = new Array<CacheFile>();
    let size = 0;
    fs.listFileSync(this.root).filter((name: string): boolean => name.endsWith('.txt'))
      .forEach((name: string): void => {
        const file = new CacheFile();
        file.path = `${this.root}/${name}`;
        const stat = fs.statSync(file.path);
        file.size = stat.size;
        file.modified = stat.mtime * 1000;
        files.push(file);
        size += file.size;
      });
    files.sort((left: CacheFile, right: CacheFile): number => left.modified - right.modified);
    files.forEach((file: CacheFile): void => {
      if (size <= 128 * 1024 * 1024 && Date.now() - file.modified <= 7 * 86400000) return;
      LibraryStore.deleteRecursively(file.path);
      LibraryStore.deleteRecursively(file.path.replace(/\.txt$/, '.json'));
      size -= file.size;
    });
  }
}
