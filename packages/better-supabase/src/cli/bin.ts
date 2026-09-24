#!/usr/bin/env node
import { run } from './index.ts';

const controller = new AbortController();
process.once('SIGINT', () => controller.abort());
process.once('SIGTERM', () => controller.abort());

const result = await run(process.argv.slice(2), {
  signal: controller.signal,
  io: {
    stdout: (text) => process.stdout.write(text),
    stderr: (text) => process.stderr.write(text),
  },
});

process.exitCode = result.code;
