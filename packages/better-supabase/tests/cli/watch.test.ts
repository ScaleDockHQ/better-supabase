import { mkdtemp, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  fileWaker,
  modifiedTime,
  onceReporter,
  parseInterval,
  sleep,
  stampFiles,
} from "../../src/cli/watch.ts";
import { CONFIG_DEFAULTS } from "../../src/config/defaults.ts";

describe("parseInterval", () => {
  it("prefers the flag, then the config, then the default", () => {
    expect(parseInterval("50", 100)).toBe(50);
    expect(parseInterval(undefined, 100)).toBe(100);
    expect(parseInterval(undefined, undefined)).toBe(
      CONFIG_DEFAULTS.gen.watchInterval,
    );
  });

  it("returns a message for a value that is not a positive number", () => {
    for (const value of ["abc", "0", "-5"]) {
      expect(parseInterval(value, undefined)).toContain("--interval");
    }
  });
});

describe("onceReporter", () => {
  it("reports a repeated message once and resets on an empty one", () => {
    const fresh = onceReporter();
    expect(fresh("boom")).toBe(true);
    expect(fresh("boom")).toBe(false);
    expect(fresh("")).toBe(false);
    expect(fresh("boom")).toBe(true);
  });
});

describe("files and sleep", () => {
  it("stamps change with the modification time, and a missing file has none", async () => {
    const dir = await mkdtemp(join(tmpdir(), "watch-"));
    const file = join(dir, "a.txt");
    await writeFile(file, "x");
    const before = await stampFiles([file]);
    await utimes(file, new Date(0), new Date(1_000_000));
    expect(await stampFiles([file])).not.toBe(before);
    expect(await modifiedTime(join(dir, "missing"))).toBeUndefined();
    expect(await modifiedTime(undefined)).toBeUndefined();
  });

  it("returns early when the signal aborts", async () => {
    const controller = new AbortController();
    controller.abort();
    await expect(sleep(60_000, controller.signal)).resolves.toBeUndefined();
  });
});

describe("fileWaker", () => {
  it("wakes on a file event, on the fallback and on abort", async () => {
    const dir = await mkdtemp(join(tmpdir(), "waker-"));
    const waker = fileWaker([dir, join(dir, "missing")], undefined);

    try {
      const woken = waker.wait(10_000);
      await sleep(50, undefined);
      await writeFile(join(dir, "a.sql"), "select 1;");
      await expect(woken).resolves.toBeUndefined();

      const started = performance.now();
      await waker.wait(30);
      expect(performance.now() - started).toBeLessThan(2000);
    } finally {
      waker.close();
    }

    const controller = new AbortController();
    const aborting = fileWaker([], controller.signal);
    const pending = aborting.wait(10_000);
    controller.abort();
    await expect(pending).resolves.toBeUndefined();
    await expect(aborting.wait(10_000)).resolves.toBeUndefined();
    aborting.close();
  });
});
