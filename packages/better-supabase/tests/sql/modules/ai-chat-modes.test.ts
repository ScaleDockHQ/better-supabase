import { describe, expect, it } from "vitest";

import { moduleBody } from "../app-columns.ts";

const body = (options: Record<string, unknown> = {}) =>
  moduleBody("ai-chat", { modules: { "ai-chat": { options } } })!;

describe("ai-chat modes", () => {
  it("adds no constraint without options.modes", () => {
    expect(body()).not.toContain("bsb_ai_chat_mode_check");
  });

  it("limits the chat mode to the listed names, idempotently", () => {
    const sql = body({ modes: ["support", "deep-research"] });

    expect(sql).toContain("bsb_ai_chat_mode_check");
    expect(sql).toContain(
      "\"mode\" is null or \"mode\" in ('support', 'deep-research')",
    );
  });

  it("refuses a mode name that is not a lowercase word", () => {
    expect(() => body({ modes: ["Sales Chat"] })).toThrow(
      'blocks.ai-chat.options.modes: "Sales Chat" is not a mode',
    );
  });
});
