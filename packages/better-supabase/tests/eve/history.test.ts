import { describe, expect, it } from "vitest";

import type { AiChat } from "../../src/blocks/ai-chat/ai-chat.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { sessionHistory } from "../../src/eve/history.ts";

const message = (id: string, role: string, text: string) => ({
  id,
  role,
  parts: text === "" ? [{ type: "step-start" }] : [{ type: "text", text }],
});

function chatsWith(path: unknown) {
  return { messages: { path: () => path } } as unknown as Pick<
    AiChat,
    "messages"
  >;
}

describe("sessionHistory", () => {
  it("returns the text messages in eve's history shape", async () => {
    const chats = chatsWith(
      AsyncResult.ok([
        message("1", "user", "hi"),
        message("2", "assistant", ""),
        message("3", "assistant", "hello"),
      ]),
    );

    expect(await sessionHistory(chats, "s")).toEqual([
      { id: "1", role: "user", text: "hi" },
      { id: "3", role: "assistant", text: "hello" },
    ]);
  });

  it("keeps the last messages when limited", async () => {
    const chats = chatsWith(
      AsyncResult.ok([
        message("1", "user", "a"),
        message("2", "assistant", "b"),
      ]),
    );

    expect(await sessionHistory(chats, "s", { limit: 1 })).toEqual([
      { id: "2", role: "assistant", text: "b" },
    ]);
  });

  it("reads an unknown session as empty", async () => {
    const chats = chatsWith(AsyncResult.err(dbError("not_found", "no chat")));

    expect(await sessionHistory(chats, "s")).toEqual([]);
  });
});
