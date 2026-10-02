#!/usr/bin/env node
import { text } from "node:stream/consumers";

import { clackPrompter } from "./prompts.ts";
import { run } from "./run.ts";
import { colorEnabled } from "./style.ts";

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
    ...(process.stdin.isTTY && process.stdout.isTTY
      ? { prompts: clackPrompter }
      : {}),
  },
});

process.exitCode = result.code;
