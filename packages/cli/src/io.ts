import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";

export interface CliIo {
  readonly stdout: (text: string) => void;
  readonly stderr: (text: string) => void;
  readonly now?: () => Date;
  /** Environment; defaults to `process.env`. */
  readonly env?: Readonly<Record<string, string | undefined>>;
}

export interface RunResult {
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

export interface CommandResult {
  readonly code: number;
  readonly output?: string;
  readonly error?: string;
}

/** Writes a file when its contents changed. Returns whether it wrote. */
export async function writeIfChanged(
  path: string,
  contents: string,
): Promise<boolean> {
  if (existsSync(path)) {
    const current = await readFile(path, "utf8");
    if (current === contents) return false;
  }
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, contents);
  return true;
}

/** Relative ESM import specifier from one file to another, keeping `.ts`. */
export function importPath(fromFile: string, toFile: string): string {
  let path = relative(dirname(fromFile), toFile).split(sep).join("/");
  if (!path.startsWith(".")) path = `./${path}`;
  return path;
}

export function display(root: string, path: string): string {
  return relative(root, resolve(root, path)).split(sep).join("/") || ".";
}
