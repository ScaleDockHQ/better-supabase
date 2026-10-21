import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody } from "../../../src/sql/render.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("messaging", { modules })!;

describe("messaging module", () => {
  it("checks its options", () => {
    for (const [options, message] of [
      [{ topic: "Bad Topic" }, /options.topic/],
      [{ threadDepth: 2 }, /options.threadDepth/],
      [{ maxBodyLength: 0 }, /options.maxBodyLength/],
      [{ maxBodyLength: 1.5 }, /options.maxBodyLength/],
      [{ editWindow: -1 }, /options.editWindow/],
      [{ editWindow: 0.5 }, /options.editWindow/],
      [{ scheduleQueue: "Bad Queue" }, /options.scheduleQueue/],
    ] as const) {
      expect(() => body({ messaging: { options } })).toThrow(message);
    }
  });

  it("flattens replies into the root unless threads nest", () => {
    const flat = body();

    const nested = body({
      messaging: { options: { threadDepth: "unlimited" } },
    });

    expect(flat).not.toBe(nested);
    expect(body({ messaging: { options: { threadDepth: 1 } } })).toBe(flat);
  });

  it("names the topic, the body limit and the edit window", () => {
    const sql = body({
      messaging: {
        options: { topic: "chat", maxBodyLength: 500, editWindow: 600 },
      },
    });

    expect(sql).toContain("'chat:'");
    expect(sql).toContain("500");
    expect(sql).toContain("600");
  });
});
