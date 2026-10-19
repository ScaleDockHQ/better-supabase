import { describe, expect, it } from "vitest";

import { createLog } from "../../../src/cli/core/log.ts";
import { plain } from "../../../src/cli/style.ts";

describe("createLog", () => {
  it("stops the spinner after the task, also when it throws", async () => {
    const lines: string[] = [];
    const spun: string[] = [];
    let clock = 0;

    const log = createLog({
      write: (line) => lines.push(line),
      paint: plain,
      debug: true,
      spinner: (message) => {
        spun.push(message);

        return () => spun.push(`done: ${message}`);
      },
      now: () => {
        clock += 5;

        return clock;
      },
    });

    expect(await log.progress("Working", async () => 1)).toBe(1);
    await expect(
      log.progress("Failing", () => Promise.reject(new Error("x"))),
    ).rejects.toThrow("x");

    expect(spun).toEqual([
      "Working",
      "done: Working",
      "Failing",
      "done: Failing",
    ]);
    expect(lines).toEqual(["debug Working: 5ms\n", "debug Failing: 5ms\n"]);
  });

  it("writes debug lines only under --debug, and runs progress without a spinner", async () => {
    const lines: string[] = [];

    const log = createLog({
      write: (line) => lines.push(line),
      paint: plain,
      debug: false,
    });

    log.debug("hidden");
    log.error("failed\n");
    expect(await log.progress("Quiet", async () => 2)).toBe(2);
    expect(lines).toEqual(["failed\n"]);
  });
});
