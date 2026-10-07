import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";

import type { Prompter } from "./prompts.ts";

export interface CliIo {
  readonly stdout: (text: string) => void;
  readonly stderr: (text: string) => void;
  /** All of stdin, for the `--*-stdin` flags that keep secrets out of arguments. */
  readonly stdin?: () => Promise<string>;
  /** Color the output with ANSI escapes. Off unless set. */
  readonly color?: boolean;
  /**
   * Prompts and spinners for a person at a terminal. `run()` drops them in
   * CI and under `--json` or `--yes`, and without them commands never ask.
   */
  readonly prompts?: Prompter;
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
  /** The JSON document `--json` prints instead of `output`. */
  readonly data?: unknown;
}

/** `text` with `\r\n` line endings turned into `\n`. */
const withLf = (text: string): string => text.replaceAll("\r\n", "\n");

/**
 * Whether a file on disk holds `expected`, ignoring line endings: a checkout
 * with `core.autocrlf` turns every `\n` into `\r\n`.
 */
export function sameText(
  current: string | undefined,
  expected: string,
): boolean {
  return current !== undefined && withLf(current) === withLf(expected);
}

/** Writes a file when its contents changed, ignoring line endings. Returns whether it wrote. */
export async function writeIfChanged(
  path: string,
  contents: string,
): Promise<boolean> {
  if (existsSync(path)) {
    const current = await readFile(path, "utf8");
    if (sameText(current, contents)) return false;
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
