import type { ModelMessage, UIMessage } from "ai";

import { describe, expect, it } from "vitest";

import {
  AI_SDK_UI_FORMAT,
  DENIED_TOOL_OUTPUT,
  fromModelMessages,
  fromUIMessage,
  isUIMessage,
  toUIMessage,
  toUIMessages,
} from "../../src/ai-sdk/index.ts";
import { type AiMessage, isAiMessage } from "../../src/blocks/ai-chat/index.ts";

const meta = { openai: { itemId: "i1" } };

const ui: UIMessage = {
  id: "a1",
  role: "assistant",
  metadata: { model: "openai/gpt-5" },
  parts: [
    { type: "step-start" },
    {
      type: "reasoning",
      text: "thinking",
      state: "done",
      providerMetadata: meta,
    },
    { type: "text", text: "Hello", state: "done", providerMetadata: meta },
    {
      type: "file",
      mediaType: "image/png",
      url: "https://x/y.png",
      filename: "y.png",
    },
    { type: "source-url", sourceId: "s1", url: "https://docs", title: "Docs" },
    {
      type: "source-document",
      sourceId: "s2",
      mediaType: "application/pdf",
      title: "Spec",
    },
    { type: "data-weather", id: "w1", data: { temp: 20 } },
    { type: "custom", kind: "openai.compaction", providerMetadata: meta },
    {
      type: "reasoning-file",
      mediaType: "image/png",
      url: "data:image/png;base64,AA",
    },
    {
      type: "tool-search",
      toolCallId: "t1",
      state: "output-available",
      input: { q: "x" },
      output: { hits: 1 },
      callProviderMetadata: meta,
      resultProviderMetadata: meta,
    },
    {
      type: "dynamic-tool",
      toolName: "mcp_lookup",
      toolCallId: "t2",
      state: "output-error",
      input: { id: 1 },
      errorText: "boom",
    },
    {
      type: "tool-delete",
      toolCallId: "t3",
      state: "approval-requested",
      input: { id: 2 },
      approval: { id: "ap3" },
    },
    {
      type: "tool-send",
      toolCallId: "t4",
      state: "output-denied",
      input: {},
      approval: { id: "ap4", approved: false, reason: "no" },
    },
    {
      type: "tool-pay",
      toolCallId: "t5",
      state: "approval-responded",
      input: { amount: 1 },
      approval: { id: "ap5", approved: true },
    },
    {
      type: "tool-wait",
      toolCallId: "t6",
      state: "input-streaming",
      providerExecuted: true,
    },
  ],
};

describe("fromUIMessage", () => {
  it("maps every AI SDK part to a valid canonical message", () => {
    const message = fromUIMessage(ui);
    expect(isAiMessage(message)).toBe(true);
    expect(message.metadata).toEqual({ model: "openai/gpt-5" });
    expect(message.parts.map((part) => part.type)).toEqual([
      "step",
      "reasoning",
      "text",
      "file",
      "source",
      "source",
      "data",
      "data",
      "data",
      "tool-call",
      "tool-result",
      "tool-call",
      "tool-result",
      "tool-call",
      "tool-approval",
      "tool-call",
      "tool-approval",
      "tool-result",
      "tool-call",
      "tool-approval",
      "tool-call",
    ]);
    expect(message.parts).toContainEqual({
      type: "tool-result",
      toolCallId: "t2",
      toolName: "mcp_lookup",
      output: "boom",
      isError: true,
    });
    expect(message.parts).toContainEqual({
      type: "tool-result",
      toolCallId: "t4",
      toolName: "send",
      output: "no",
      isError: true,
    });
    expect(message.parts).toContainEqual({
      type: "tool-call",
      toolCallId: "t6",
      toolName: "wait",
      input: {},
      providerExecuted: true,
    });
    expect(message.parts).toContainEqual({
      type: "data",
      name: "ui.custom",
      data: { kind: "openai.compaction" },
      providerMetadata: meta,
    });
  });

  it("drops unknown parts and non-object metadata", () => {
    const message = fromUIMessage({
      id: "u1",
      role: "user",
      metadata: "x",
      parts: [{ type: "future" } as unknown as UIMessage["parts"][number]],
    });
    expect(message).toEqual({ id: "u1", role: "user", parts: [] });
  });

  it("uses the reason-less denial output", () => {
    const message = fromUIMessage({
      id: "a",
      role: "assistant",
      parts: [
        {
          type: "tool-x",
          toolCallId: "t",
          state: "output-denied",
          input: {},
          approval: { id: "ap", approved: false },
        },
      ],
    });
    expect(message.parts.at(-1)).toMatchObject({ output: DENIED_TOOL_OUTPUT });
  });
});

describe("toUIMessage", () => {
  it("round-trips the parts it can represent", () => {
    const back = toUIMessage(fromUIMessage(ui));
    expect(back.id).toBe("a1");
    expect(back.metadata).toEqual({ model: "openai/gpt-5" });
    const types = back.parts.map((part) => part.type);
    expect(types).toEqual([
      "step-start",
      "reasoning",
      "text",
      "file",
      "source-url",
      "source-document",
      "data-weather",
      "custom",
      "reasoning-file",
      "tool-search",
      "tool-mcp_lookup",
      "tool-delete",
      "tool-send",
      "tool-pay",
      "tool-wait",
    ]);
    expect(back.parts[9]).toEqual(ui.parts[9]);
    expect(back.parts[10]).toMatchObject({
      state: "output-error",
      errorText: "boom",
    });
    expect(back.parts[11]).toEqual(ui.parts[11]);
    expect(back.parts[12]).toEqual(ui.parts[12]);
    expect(back.parts[13]).toEqual(ui.parts[13]);
    expect(back.parts[14]).toMatchObject({
      state: "input-available",
      providerExecuted: true,
    });
  });

  it("returns the stored native message", () => {
    const stored = {
      ...fromUIMessage(ui),
      format: AI_SDK_UI_FORMAT,
      native: ui,
    };
    expect(toUIMessage(stored)).toBe(ui);
  });

  it("covers the remaining tool states and fallbacks", () => {
    const message: AiMessage = {
      id: "m",
      role: "tool",
      metadata: { a: 1 },
      parts: [
        { type: "tool-result", toolCallId: "orphan", toolName: "x", output: 1 },
        { type: "tool-call", toolCallId: "d", toolName: "deny", input: {} },
        {
          type: "tool-approval",
          toolCallId: "d",
          approvalId: "ad",
          state: "denied",
        },
        { type: "tool-call", toolCallId: "e", toolName: "err", input: {} },
        {
          type: "tool-approval",
          toolCallId: "e",
          approvalId: "ae",
          state: "approved",
        },
        {
          type: "tool-result",
          toolCallId: "e",
          toolName: "err",
          output: { code: 1 },
          isError: true,
        },
        { type: "tool-call", toolCallId: "o", toolName: "ok", input: {} },
        {
          type: "tool-result",
          toolCallId: "o",
          toolName: "ok",
          output: 2,
          providerMetadata: meta,
        },
        { type: "step", boundary: "finish" },
        { type: "source", sourceType: "url", id: "s" },
        { type: "source", sourceType: "document", id: "d2" },
        { type: "data", name: "ui.custom", data: { kind: "nodot" } },
        { type: "data", name: "ui.reasoning-file", data: { url: 1 } },
        { type: "data", name: "plain", data: 1, providerMetadata: { bad: 1 } },
      ],
    };
    const back = toUIMessage(message);
    expect(back.role).toBe("assistant");
    expect(back.parts).toEqual([
      {
        type: "tool-deny",
        toolCallId: "d",
        input: {},
        state: "approval-responded",
        approval: { id: "ad", approved: false },
      },
      {
        type: "tool-err",
        toolCallId: "e",
        input: {},
        state: "output-error",
        approval: { id: "ae", approved: true },
        errorText: '{"code":1}',
      },
      {
        type: "tool-ok",
        toolCallId: "o",
        input: {},
        state: "output-available",
        output: 2,
        resultProviderMetadata: meta,
      },
      { type: "source-url", sourceId: "s", url: "" },
      {
        type: "source-document",
        sourceId: "d2",
        mediaType: "application/octet-stream",
        title: "",
      },
      { type: "data-plain", data: 1 },
    ]);
  });
});

describe("toUIMessages", () => {
  it("folds later tool messages into the call's assistant message", () => {
    const history: AiMessage[] = [
      { id: "u", role: "user", parts: [{ type: "text", text: "hi" }] },
      {
        id: "a",
        role: "assistant",
        parts: [
          { type: "tool-call", toolCallId: "t", toolName: "get", input: {} },
        ],
      },
      {
        id: "tm",
        role: "tool",
        parts: [
          { type: "tool-result", toolCallId: "t", toolName: "get", output: 3 },
        ],
      },
      {
        id: "n",
        role: "assistant",
        parts: [{ type: "text", text: "done" }],
      },
    ];
    const out = toUIMessages(history);
    expect(out.map((message) => message.id)).toEqual(["u", "a", "n"]);
    expect(out[1]?.parts[0]).toMatchObject({
      type: "tool-get",
      state: "output-available",
      output: 3,
    });
  });

  it("keeps native messages and a leading tool message", () => {
    const native: UIMessage = { id: "x", role: "assistant", parts: [] };
    const out = toUIMessages([
      { id: "t", role: "tool", parts: [] },
      {
        id: "x",
        role: "assistant",
        parts: [],
        format: AI_SDK_UI_FORMAT,
        native,
      } as AiMessage,
      { id: "t2", role: "tool", parts: [] },
    ]);
    expect(out.map((message) => [message.id, message.role])).toEqual([
      ["t", "assistant"],
      ["x", "assistant"],
      ["t2", "assistant"],
    ]);
    expect(out[1]).toBe(native);
  });
});

describe("isUIMessage", () => {
  it("checks the shape", () => {
    expect(isUIMessage(ui)).toBe(true);
    expect(isUIMessage({ id: "a", role: "tool", parts: [] })).toBe(false);
    expect(isUIMessage(null)).toBe(false);
  });
});

describe("fromModelMessages", () => {
  const turn: ModelMessage[] = [
    {
      role: "assistant",
      content: [
        { type: "reasoning", text: "plan" },
        { type: "text", text: "Looking." },
        {
          type: "file",
          mediaType: "image/png",
          data: new URL("https://a.b/c.png"),
        },
        {
          type: "file",
          mediaType: "image/png",
          data: "iVBORw0K",
          filename: "x.png",
        },
        {
          type: "file",
          mediaType: "text/plain",
          data: "data:text/plain,hi",
          filename: "hi.txt",
        },
        {
          type: "reasoning-file",
          mediaType: "image/png",
          data: { type: "url", url: new URL("https://a.b/r.png") },
        },
        { type: "custom", kind: "openai.compaction" },
        {
          type: "tool-call",
          toolCallId: "t1",
          toolName: "search",
          input: { q: "x" },
          providerExecuted: true,
        },
        {
          type: "tool-call",
          toolCallId: "t2",
          toolName: "remove",
          input: undefined,
        },
        {
          type: "tool-approval-request",
          approvalId: "approval-t2",
          toolCallId: "t2",
        },
      ],
    },
    {
      role: "tool",
      content: [
        {
          type: "tool-result",
          toolCallId: "t1",
          toolName: "search",
          output: { type: "json", value: { hits: 1 } },
        },
        {
          type: "tool-approval-response",
          approvalId: "approval-t2",
          approved: false,
          reason: "no",
        },
        {
          type: "tool-approval-response",
          approvalId: "unknown",
          approved: true,
        },
        {
          type: "tool-result",
          toolCallId: "t2",
          toolName: "remove",
          output: { type: "execution-denied", reason: "no" },
        },
      ],
    },
    { role: "assistant", content: "Left it." },
    { role: "assistant", content: "" },
    {
      role: "tool",
      content: [
        {
          type: "tool-result",
          toolCallId: "t3",
          toolName: "fail",
          output: { type: "error-text", value: "bad" },
        },
        {
          type: "tool-result",
          toolCallId: "t4",
          toolName: "gone",
          output: { type: "execution-denied" },
        },
        {
          type: "tool-result",
          toolCallId: "t5",
          toolName: "say",
          output: { type: "text", value: "hi" },
        },
      ],
    },
  ];

  it("converts an agent's turn into one canonical answer", () => {
    const message = fromModelMessages("m1", turn, {
      sources: [
        {
          type: "source",
          sourceType: "url",
          id: "s1",
          url: "https://a.b",
          title: "A",
        },
        {
          type: "source",
          sourceType: "document",
          id: "s2",
          mediaType: "application/pdf",
          title: "D",
          providerMetadata: meta,
        },
      ],
    });
    expect(isAiMessage(message)).toBe(true);
    expect(message).toEqual({
      id: "m1",
      role: "assistant",
      parts: [
        { type: "step", boundary: "start", stepId: "m1:0" },
        { type: "reasoning", text: "plan", state: "done" },
        { type: "text", text: "Looking.", state: "done" },
        { type: "file", mediaType: "image/png", url: "https://a.b/c.png" },
        {
          type: "file",
          mediaType: "text/plain",
          url: "data:text/plain,hi",
          filename: "hi.txt",
        },
        {
          type: "data",
          name: "ui.reasoning-file",
          data: { mediaType: "image/png", url: "https://a.b/r.png" },
        },
        {
          type: "data",
          name: "ui.custom",
          data: { kind: "openai.compaction" },
        },
        {
          type: "tool-call",
          toolCallId: "t1",
          toolName: "search",
          input: { q: "x" },
          providerExecuted: true,
        },
        { type: "tool-call", toolCallId: "t2", toolName: "remove", input: {} },
        {
          type: "tool-approval",
          toolCallId: "t2",
          approvalId: "approval-t2",
          state: "denied",
          reason: "no",
        },
        {
          type: "tool-result",
          toolCallId: "t1",
          toolName: "search",
          output: { hits: 1 },
        },
        {
          type: "tool-result",
          toolCallId: "t2",
          toolName: "remove",
          output: "no",
          isError: true,
        },
        { type: "step", boundary: "start", stepId: "m1:1" },
        { type: "text", text: "Left it.", state: "done" },
        { type: "step", boundary: "start", stepId: "m1:2" },
        {
          type: "tool-result",
          toolCallId: "t3",
          toolName: "fail",
          output: "bad",
          isError: true,
        },
        {
          type: "tool-approval",
          toolCallId: "t4",
          approvalId: "approval-t4",
          state: "denied",
          reason: DENIED_TOOL_OUTPUT,
        },
        {
          type: "tool-result",
          toolCallId: "t4",
          toolName: "gone",
          output: DENIED_TOOL_OUTPUT,
          isError: true,
        },
        {
          type: "tool-result",
          toolCallId: "t5",
          toolName: "say",
          output: "hi",
        },
        {
          type: "source",
          sourceType: "url",
          id: "s1",
          url: "https://a.b",
          title: "A",
        },
        {
          type: "source",
          sourceType: "document",
          id: "s2",
          title: "D",
          mediaType: "application/pdf",
          providerMetadata: meta,
        },
      ],
    });
  });

  it("keeps decisions the agent stripped from its messages", () => {
    const message = fromModelMessages(
      "m1",
      [
        {
          role: "assistant",
          content: [
            {
              type: "tool-call",
              toolCallId: "t1",
              toolName: "remove",
              input: {},
            },
          ],
        },
      ],
      {
        approvals: [
          {
            approvalId: "approval-t1",
            toolCallId: "t1",
            state: "approved",
            reason: "fine",
          },
          { approvalId: "approval-t9", toolCallId: "t9", state: "requested" },
        ],
      },
    );
    expect(message.parts.slice(2)).toEqual([
      {
        type: "tool-approval",
        toolCallId: "t1",
        approvalId: "approval-t1",
        state: "approved",
        reason: "fine",
      },
      {
        type: "tool-approval",
        toolCallId: "t9",
        approvalId: "approval-t9",
        state: "requested",
      },
    ]);
  });
});
