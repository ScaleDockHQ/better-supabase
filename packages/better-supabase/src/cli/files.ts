import { resolve } from "node:path";

import type { CommandResult } from "./io.ts";

import { fileDiff } from "./diff.ts";
import { display, readIfExists, sameText, writeIfChanged } from "./io.ts";

/** What a generated file looks like on disk next to what the command would write. */
export interface FileState {
  /** The path shown to people, relative to the project root. */
  readonly file: string;
  readonly path: string;
  readonly current: string | undefined;
  /** What the command would write. */
  readonly contents: string;
  readonly upToDate: boolean;
}

/** Reads `out` under `root` and compares it with `contents`, ignoring line endings. */
export async function fileState(
  root: string,
  out: string,
  contents: string,
): Promise<FileState> {
  const path = resolve(root, out);
  const current = await readIfExists(path);

  return {
    file: display(root, out),
    path,
    current,
    contents,
    upToDate: sameText(current, contents),
  };
}

/**
 * The result of `--check` for one file: up to date, or failed with a unified
 * diff of the drift and the command that rewrites it.
 */
export function staleResult(
  state: FileState,
  regenerate: string,
): CommandResult {
  return state.upToDate
    ? { code: 0, output: `${state.file} is up to date.` }
    : {
        code: 1,
        output: fileDiff(state.file, state.current, state.contents),
        error: `${state.file} is out of date. Run \`${regenerate}\`.`,
      };
}

/** Writes `contents` when it changed and returns the `Wrote` or `Unchanged` line for `shown`. */
export async function writeLine(
  path: string,
  contents: string,
  shown: string,
  suffix = "",
  options: { readonly mode?: number } = {},
): Promise<{ readonly wrote: boolean; readonly line: string }> {
  const wrote = await writeIfChanged(path, contents, options);

  return { wrote, line: `${wrote ? "Wrote" : "Unchanged"} ${shown}${suffix}` };
}
