#!/usr/bin/env node
import { existsSync } from "node:fs";
import { basename } from "node:path";
import { text } from "node:stream/consumers";

import type * as PromptsModule from "./prompts.ts";
import type { Prompter } from "./prompts.ts";

import { run } from "./core/run.ts";
import { colorEnabled } from "./style.ts";

// @clack/prompts loads only when a command asks something or shows progress.
const clackModule = (): Promise<typeof PromptsModule> => import("./prompts.ts");

const clack = (): Promise<Prompter> =>
  clackModule().then((module) => module.createClackPrompter(process.stderr));

const prompts: Prompter = {
  select: async (message, choices, initial) =>
    (await clack()).select(message, choices, initial),
  multiselect: async (message, choices, initial) =>
    (await clack()).multiselect(message, choices, initial),
  confirm: async (message) => (await clack()).confirm(message),
};

/** A spinner on a terminal; a plain line in a pipe or a CI log. */
const spinner = (message: string): (() => void) => {
  if (!process.stderr.isTTY) {
    process.stderr.write(`${message}...\n`);

    return () => {};
  }

  let stop: (() => void) | undefined;
  let stopped = false;
  void clackModule().then((module) => {
    if (!stopped) {
      stop = module.clackSpinner(process.stderr, message);
    }
  });

  return () => {
    stopped = true;
    stop?.();
  };
};

const controller = new AbortController();
let signalExit: 130 | 143 | undefined;

process.once("SIGINT", () => {
  signalExit = 130;
  controller.abort();
});

process.once("SIGTERM", () => {
  signalExit = 143;
  controller.abort();
});

// A symlinked bin keeps the typed name in argv[1]; shims that run the file
// directly (pnpm, Windows) report better-supabase.
const invoked = basename(process.argv[1] ?? "", ".js");

const result = await run(process.argv.slice(2), {
  bin: invoked === "bsb" ? "bsb" : "better-supabase",
  cwd: process.cwd(),
  env: process.env,
  signal: controller.signal,
  io: {
    stdout: (chunk) => {
      process.stdout.write(chunk);
    },
    stderr: (chunk) => {
      process.stderr.write(chunk);
    },
    stdin: () => text(process.stdin),
    stdinIsTty: process.stdin.isTTY,
    stdoutIsTty: process.stdout.isTTY,
    exists: existsSync,
    color: colorEnabled(process.stdout),
    stderrColor: colorEnabled(process.stderr),
    spinner,
    ...(process.stdin.isTTY && process.stdout.isTTY ? { prompts } : {}),
  },
});

process.exitCode = signalExit ?? result.code;
