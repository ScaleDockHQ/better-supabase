import { describe, expect, it, vi } from "vitest";

import type { AiChat } from "../../../src/blocks/ai-chat/index.ts";

import { AI_SDK_UI_FORMAT } from "../../../src/ai-sdk/index.ts";
import {
  durableSteps,
  runDurableStep,
} from "../../../src/ai-sdk/workflow/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";

const result = <T>(value: T) => AsyncResult.from(async () => ok(value));

function fakeChats(failSave = false) {
  const calls: { name: string; args: unknown[] }[] = [];
  const record =
    <T>(name: string, value: T) =>
    (...args: unknown[]) => {
      calls.push({ name, args });
      return result(value);
    };
  const api = {
    messages: {
      saveAssistant: (...args: unknown[]) => {
        calls.push({ name: "saveAssistant", args });
        return failSave
          ? AsyncResult.from(async () => err(dbError("unexpected", "down")))
          : result({ messageId: "m1", parentId: "u1", created: true });
      },
    },
    approvals: {
      request: record("request", {}),
      list: record("list", [
        { approvalId: "a1", decision: "approved", reason: undefined },
        { approvalId: "a2", decision: "denied", reason: "no" },
        { approvalId: "a3", decision: "pending", reason: undefined },
      ]),
    },
    runs: { release: record("release", true) },
  };
  // SAFETY: the fake implements the calls the steps make.
  return { chats: api as unknown as AiChat, calls };
}

const message = {
  id: "m1",
  role: "assistant" as const,
  parts: [{ type: "text" as const, text: "Hi", state: "done" as const }],
};

describe("durable steps", () => {
  it("saves the answer with its AI SDK form", async () => {
    const { chats, calls } = fakeChats();
    await runDurableStep(chats, "save", {
      chatId: "c1",
      message,
      parentId: "u1",
      model: "openai/gpt-5",
      runId: "run1",
      status: "complete",
    });
    expect(calls[0]).toEqual({
      name: "saveAssistant",
      args: [
        "c1",
        message,
        {
          parentId: "u1",
          status: "complete",
          model: "openai/gpt-5",
          format: AI_SDK_UI_FORMAT,
          native: {
            id: "m1",
            role: "assistant",
            parts: [{ type: "text", text: "Hi", state: "done" }],
          },
          runId: "run1",
        },
      ],
    });
  });

  it("throws on a database error so the step retries", async () => {
    const { chats } = fakeChats(true);
    await expect(
      runDurableStep(chats, "save", {
        chatId: "c1",
        message,
        parentId: "u1",
        model: "openai/gpt-5",
        runId: "run1",
        status: "complete",
      }),
    ).rejects.toMatchObject({ kind: "unexpected" });
  });

  it("records each approval request", async () => {
    const { chats, calls } = fakeChats();
    await durableSteps(chats).approvals({
      chatId: "c1",
      runId: "run1",
      messageId: "m1",
      requests: [
        { approvalId: "a1", toolCallId: "t1", toolName: "rm", input: {} },
        {
          approvalId: "a2",
          toolCallId: "t2",
          toolName: "rm",
          input: { p: 1 },
          signature: "sig",
        },
      ],
    });
    expect(calls.map((call) => call.args)).toEqual([
      [
        "c1",
        {
          approvalId: "a1",
          tool: "rm",
          toolCallId: "t1",
          input: {},
          runId: "run1",
          messageId: "m1",
        },
      ],
      [
        "c1",
        {
          approvalId: "a2",
          tool: "rm",
          toolCallId: "t2",
          input: { p: 1 },
          runId: "run1",
          messageId: "m1",
          signature: "sig",
        },
      ],
    ]);
  });

  it("reads back only decided approvals", async () => {
    const { chats, calls } = fakeChats();
    await expect(
      runDurableStep(chats, "decisions", {
        chatId: "c1",
        approvalIds: ["a1", "a2", "a3"],
      }),
    ).resolves.toEqual([
      { approvalId: "a1", approved: true },
      { approvalId: "a2", approved: false, reason: "no" },
    ]);
    expect(calls[0]?.args).toEqual(["c1", ["a1", "a2", "a3"]]);
  });

  it("releases the segment and backfills a missing cost", async () => {
    const { chats, calls } = fakeChats();
    const enqueueCostBackfill = vi.fn(async () => undefined);
    await runDurableStep(
      chats,
      "release",
      {
        chatId: "c1",
        streamId: "s1",
        organizationId: "org",
        status: "done",
        usage: { inputTokens: 1, outputTokens: 2, generationId: "gen_1" },
      },
      { enqueueCostBackfill },
    );
    expect(calls[0]?.args).toEqual([
      "c1",
      "s1",
      {
        status: "done",
        usage: { inputTokens: 1, outputTokens: 2 },
        generationId: "gen_1",
      },
    ]);
    expect(enqueueCostBackfill).toHaveBeenCalledWith({
      generationId: "gen_1",
      organizationId: "org",
    });
  });

  it("releases with an error and no backfill without a generation", async () => {
    const { chats, calls } = fakeChats();
    const enqueueCostBackfill = vi.fn(async () => undefined);
    await durableSteps(chats, { enqueueCostBackfill }).release({
      chatId: "c1",
      streamId: "s1",
      organizationId: "org",
      status: "error",
      error: "down",
    });
    expect(calls[0]?.args[2]).toEqual({ status: "error", error: "down" });
    expect(enqueueCostBackfill).not.toHaveBeenCalled();
  });
});
