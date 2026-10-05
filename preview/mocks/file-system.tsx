/** In-memory stand-in for the app's two file uses: the settings file and the library's directory. */
const files = new Map<string, string>();
const dirs = new Set<string>();

export const Paths = { document: { uri: 'file:///preview/documents/' } };

export class Directory {
  uri: string;
  constructor(base: { uri: string }, name: string) {
    this.uri = `${base.uri}${name}/`;
  }
  get exists() {
    return dirs.has(this.uri);
  }
  create() {
    dirs.add(this.uri);
  }
  delete() {
    dirs.delete(this.uri);
  }
}

export class File {
  private key: string;
  constructor(base: { uri: string }, name: string) {
    this.key = `${base.uri}${name}`;
  }
  get exists() {
    return files.has(this.key);
  }
  create() {
    if (!files.has(this.key)) files.set(this.key, '');
  }
  textSync() {
    return files.get(this.key) ?? '';
  }
  write(content: string) {
    files.set(this.key, content);
  }
  delete() {
    files.delete(this.key);
  }
}
