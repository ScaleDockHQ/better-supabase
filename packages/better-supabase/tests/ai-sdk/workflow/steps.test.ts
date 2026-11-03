import { describe, expect, it, vi } from "vitest";
import { FatalError, RetryableError } from "workflow";

import type { AiChat } from "../../../src/blocks/ai-chat/index.ts";

import { AI_SDK_UI_FORMAT } from "../../../src/ai-sdk/index.ts";
import {
  durableStepError,
  durableSteps,
  runDurableStep,
} from "../../../src/ai-sdk/workflow/index.ts";
import { DbException } from "../../../src/core/db-exception.ts";
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
        {
          chatId: "c1",
          message,
          options: {
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
        {
          chatId: "c1",
          request: {
            approvalId: "a1",
            tool: "rm",
            toolCallId: "t1",
            input: {},
            runId: "run1",
            messageId: "m1",
          },
        },
      ],
      [
        {
          chatId: "c1",
          request: {
            approvalId: "a2",
            tool: "rm",
            toolCallId: "t2",
            input: { p: 1 },
            runId: "run1",
            messageId: "m1",
            signature: "sig",
          },
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
    expect(calls[0]?.args).toEqual([
      { chatId: "c1", approvalIds: ["a1", "a2", "a3"] },
    ]);
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
        status: "completed",
        usage: {
          inputTokens: 1,
          outputTokens: 2,
          totalTokens: 3,
          cachedInputTokens: 0,
          reasoningTokens: 0,
          generationId: "gen_1",
          costMicroUsd: undefined,
        },
      },
      { enqueueCostBackfill },
    );
    expect(calls[0]?.args).toEqual([
      {
        chatId: "c1",
        streamId: "s1",
        status: "completed",
        usage: {
          inputTokens: 1,
          outputTokens: 2,
          totalTokens: 3,
          cachedInputTokens: 0,
          reasoningTokens: 0,
        },
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
      status: "failed",
      error: "down",
    });
    expect(calls[0]?.args[0]).toMatchObject({
      status: "failed",
      error: "down",
    });
    expect(enqueueCostBackfill).not.toHaveBeenCalled();
  });
});

describe("durableStepError", () => {
  it("makes permanent failures fatal", () => {
    for (const kind of ["forbidden", "not_found", "conflict"] as const) {
      expect(
        durableStepError(new DbException(dbError(kind, "no"))),
      ).toBeInstanceOf(FatalError);
    }
  });

  it("retries rate limits after retryAfter", () => {
    const mapped = durableStepError(
      new DbException(dbError("rate_limited", "slow", { retryAfter: 3 })),
    );

    expect(mapped).toBeInstanceOf(RetryableError);
    expect((mapped as RetryableError).retryAfter.getTime()).toBeGreaterThan(
      Date.now() + 2000,
    );
  });

  it("leaves other errors to the default retries", () => {
    const network = new DbException(dbError("network", "down"));

    expect(durableStepError(network)).toBe(network);

    const plain = new Error("x");

    expect(durableStepError(plain)).toBe(plain);
  });

  it("maps a failing step", async () => {
    const chats = {
      messages: {
        saveAssistant: () =>
          AsyncResult.from(async () => err(dbError("forbidden", "no"))),
      },
    } as unknown as AiChat;

    await expect(
      runDurableStep(chats, "save", {
        chatId: "c",
        message: { id: "m", role: "assistant", parts: [] },
        parentId: "u",
        status: "completed",
        model: "x",
        runId: "r",
      } as never),
    ).rejects.toBeInstanceOf(FatalError);
  });
});
