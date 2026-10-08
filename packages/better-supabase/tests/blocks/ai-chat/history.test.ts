import { describe, expect, it } from "vitest";

import type { AiMessage } from "../../../src/blocks/ai-chat/index.ts";

import {
  INTERRUPTED_TOOL_OUTPUT,
  pathToHistory,
  repairDanglingToolCalls,
  validateMessage,
} from "../../../src/blocks/ai-chat/index.ts";

describe("validateMessage", () => {
  it("accepts a canonical message and reports issues otherwise", () => {
    const message = {
      id: "m1",
      role: "user",
      parts: [{ type: "text", text: "hi" }],
    };
    expect(validateMessage(message)).toEqual({ ok: true, message });
    expect(validateMessage({ id: "m1", role: "robot", parts: [] })).toEqual({
      ok: false,
      issues: [expect.objectContaining({ message: expect.any(String) })],
    });
  });
});

describe("pathToHistory", () => {
  it("drops the tree's fields", () => {
    expect(
      pathToHistory([
        { id: "m1", role: "user", parts: [], parentId: undefined },
        {
          id: "m2",
          role: "assistant",
          parts: [{ type: "text", text: "ok" }],
          metadata: { tokens: 1 },
          parentId: "m1",
        },
      ]),
    ).toEqual([
      { id: "m1", role: "user", parts: [] },
      {
        id: "m2",
        role: "assistant",
        parts: [{ type: "text", text: "ok" }],
        metadata: { tokens: 1 },
      },
    ]);
  });
});

describe("repairDanglingToolCalls", () => {
  it("closes calls without a result and leaves the rest alone", () => {
    const messages: AiMessage[] = [
      { id: "u", role: "user", parts: [{ type: "text", text: "go" }] },
      {
        id: "a",
        role: "assistant",
        parts: [
          { type: "tool-call", toolCallId: "t1", toolName: "x", input: {} },
          { type: "tool-call", toolCallId: "t2", toolName: "y", input: {} },
          {
            type: "tool-call",
            toolCallId: "t3",
            toolName: "z",
            input: {},
            providerExecuted: true,
          },
          { type: "tool-call", toolCallId: "t4", toolName: "w", input: {} },
          {
            type: "tool-approval",
            toolCallId: "t4",
            approvalId: "ap",
            state: "requested",
          },
        ],
      },
      {
        id: "t",
        role: "tool",
        parts: [
          { type: "tool-result", toolCallId: "t2", toolName: "y", output: 1 },
        ],
      },
    ];
    const repaired = repairDanglingToolCalls(messages);
    expect(repaired[0]).toBe(messages[0]);
    expect(repaired[2]).toBe(messages[2]);
    expect(repaired[1]?.parts.map((part) => part.type)).toEqual([
      "tool-call",
      "tool-result",
      "tool-call",
      "tool-call",
      "tool-call",
      "tool-approval",
    ]);
    expect(repaired[1]?.parts[1]).toEqual({
      type: "tool-result",
      toolCallId: "t1",
      toolName: "x",
      output: INTERRUPTED_TOOL_OUTPUT,
      isError: true,
    });
  });
});
