#!/usr/bin/env node
import { text } from "node:stream/consumers";

import type { Prompter } from "./prompts.ts";

import { run } from "./run.ts";
import { colorEnabled } from "./style.ts";

// @clack/prompts loads only when a command asks something.
const clack = (): Promise<Prompter> =>
  import("./prompts.ts").then((module) => module.clackPrompter);

const prompts: Prompter = {
  select: async (message, choices, initial) =>
    (await clack()).select(message, choices, initial),
  multiselect: async (message, choices, initial) =>
    (await clack()).multiselect(message, choices, initial),
  confirm: async (message) => (await clack()).confirm(message),
  spinner: (message) => {
    let stop: (() => void) | undefined;
    let stopped = false;
    void clack().then((prompter) => {
      if (!stopped) stop = prompter.spinner(message);
    });
    return () => {
      stopped = true;
      stop?.();
    };
  },
};

const controller = new AbortController();
process.once("SIGINT", () => {
  controller.abort();
});
process.once("SIGTERM", () => {
  controller.abort();
});

const result = await run(process.argv.slice(2), {
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
    color: colorEnabled(),
    ...(process.stdin.isTTY && process.stdout.isTTY ? { prompts } : {}),
  },
});

process.exitCode = controller.signal.aborted ? 130 : result.code;
