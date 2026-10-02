#!/usr/bin/env node
import { clackPrompter } from "./prompts.ts";
import { run } from "./run.ts";
import { colorEnabled } from "./style.ts";

const controller = new AbortController();
process.once("SIGINT", () => controller.abort());
process.once("SIGTERM", () => controller.abort());

const result = await run(process.argv.slice(2), {
  signal: controller.signal,
  io: {
    stdout: (text) => process.stdout.write(text),
    stderr: (text) => process.stderr.write(text),
    color: colorEnabled(),
    ...(process.stdin.isTTY && process.stdout.isTTY && !process.env["CI"]
      ? { prompts: clackPrompter }
      : {}),
  },
});

process.exitCode = result.code;
