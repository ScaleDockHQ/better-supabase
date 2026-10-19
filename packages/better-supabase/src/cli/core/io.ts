import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";

import type { Prompter } from "../prompts.ts";

import { CliError, type CliErrorCode } from "./errors.ts";

export interface CliIo {
  readonly stdout: (text: string) => void;
  readonly stderr: (text: string) => void;
  /** All of stdin, for the `--*-stdin` flags that keep secrets out of arguments. */
  readonly stdin?: () => Promise<string>;
  /** Stdin is a terminal, so reading it would wait for typing instead of a pipe. */
  readonly stdinIsTty?: boolean;
  /** Color stdout with ANSI escapes. Off unless set; `--no-color` turns it off. */
  readonly color?: boolean;
  /** Color stderr with ANSI escapes. Defaults to `color`. */
  readonly stderrColor?: boolean;
  /**
   * Shows `message` on stderr until the returned function is called: a
   * spinner on a terminal, a plain line elsewhere. Without it, progress
   * shows nothing.
   */
  readonly spinner?: (message: string) => () => void;
  /**
   * Prompts for a person at a terminal. `run()` drops them in CI and under
   * `--json` or `--yes`, and without them commands never ask.
   */
  readonly prompts?: Prompter;
}

export interface RunResult {
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

/** A command to run next, and when it applies. */
export interface NextStep {
  readonly command: string;
  readonly when: string;
}

export interface CommandResult {
  readonly code: number;
  readonly output?: string;
  readonly error?: string;
  /**
   * The error code `--json` reports when `code` is not 0. Without it, exit
   * code 2 reports `usage`, 3 `input_required`, 130 `cancelled`, and any
   * other `failed`.
   */
  readonly errorCode?: CliErrorCode;
  /** The `data` of the `--json` envelope. */
  readonly data?: unknown;
  readonly next?: readonly NextStep[];
  /**
   * Printed on stdout exactly as is, in place of `output` and the envelope:
   * a document another tool reads, like `gen --metadata` without `--out`.
   */
  readonly raw?: string;
  /** The command already printed its results through `emit`, so `run()` prints nothing more. */
  readonly streamed?: boolean;
}

/**
 * All of stdin for `flag`. Fails at once when stdin is a terminal or
 * missing, instead of waiting for input nobody pipes in.
 */
export async function readStdin(io: CliIo, flag: string): Promise<string> {
  if (!io.stdin || io.stdinIsTty === true) {
    throw new CliError(
      "missing_value",
      `${flag} reads from stdin, and nothing is piped in. Pipe the value: printf %s "$VALUE" | better-supabase <command> ${flag}`,
      { flag },
    );
  }

  return io.stdin();
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

/** The file's text, or `undefined` when it does not exist. */
export async function readIfExists(path: string): Promise<string | undefined> {
  return existsSync(path) ? readFile(path, "utf-8") : undefined;
}

/** Relative ESM import specifier from one file to another, keeping `.ts`. */
export function importPath(fromFile: string, toFile: string): string {
  let path = relative(dirname(fromFile), toFile).split(sep).join("/");

  if (!path.startsWith(".")) {
    path = `./${path}`;
  }

  return path;
}

export function display(root: string, path: string): string {
  return relative(root, resolve(root, path)).split(sep).join("/") || ".";
}
