import type { ModelCallStreamPart } from "@ai-sdk/workflow";
import type { ModelMessage } from "ai";

import { describe, expect, it, vi } from "vitest";

import {
  type DurableAgentArgs,
  type DurableAgentResult,
  type DurableHook,
  type DurableSaveInput,
  type DurableStep,
  type DurableTurnInput,
  durableStopToken,
  durableTurn,
  durableTurnToken,
} from "../../../src/ai-sdk/workflow/index.ts";

interface Controlled<T> {
  readonly hook: DurableHook<T>;
  push(value: T): void;
}

function controlled<T>(): Controlled<T> {
  const queue: T[] = [];
  let wake: (() => void) | undefined;
  let resolveFirst: (value: T) => void = () => undefined;
  const first = new Promise<T>((resolve) => {
    resolveFirst = resolve;
  });
  const next = async (): Promise<IteratorResult<T>> => {
    if (queue.length === 0)
      await new Promise<void>((resolve) => {
        wake = resolve;
      });
    return { done: false, value: queue.shift()! };
  };
  const hook: DurableHook<T> = Object.assign(first, {
    [Symbol.asyncIterator]: () => ({ next }),
  });
  return {
    hook,
    push(value) {
      resolveFirst(value);
      queue.push(value);
      wake?.();
    },
  };
}

const user: ModelMessage = {
  role: "user",
  content: [{ type: "text", text: "Delete a.txt" }],
};

const input: DurableTurnInput = {
  chatId: "c1",
  organizationId: "org",
  userId: "user",
  model: "openai/gpt-5",
  messageId: "m1",
  parentId: "u1",
  runId: "run1",
  streamId: "s1",
  messages: [user],
  providerOptions: { gateway: { user: "user" } },
};

const usage = {
  inputTokens: 5,
  inputTokenDetails: {
    noCacheTokens: 5,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
  },
  outputTokens: 2,
  outputTokenDetails: { textTokens: 2, reasoningTokens: 0 },
  totalTokens: 7,
};

function answer(text: string): ModelMessage {
  return { role: "assistant", content: [{ type: "text", text }] };
}

const asking: ModelMessage = {
  role: "assistant",
  content: [
    {
      type: "tool-call",
      toolCallId: "t1",
      toolName: "remove",
      input: { path: "a.txt" },
    },
    {
      type: "tool-approval-request",
      approvalId: "approval-t1",
      toolCallId: "t1",
      signature: "sig",
    },
  ],
};

interface Harness {
  readonly stop: Controlled<object>;
  readonly turn: Controlled<{ streamId: string; runId: string }>;
  readonly calls: { name: string; input: unknown }[];
  readonly agentArgs: DurableAgentArgs[];
  readonly namespaces: string[];
  readonly run: () => ReturnType<typeof durableTurn>;
}

function harness(
  agent: (args: DurableAgentArgs) => Promise<DurableAgentResult>,
  decisions: () => unknown[] = () => [],
): Harness {
  const stop = controlled<object>();
  const turn = controlled<{ streamId: string; runId: string }>();
  const tokens = new Map<string, DurableHook<unknown>>([
    [durableStopToken("wrun"), stop.hook],
    [durableTurnToken("wrun"), turn.hook],
  ]);
  const calls: { name: string; input: unknown }[] = [];
  const agentArgs: DurableAgentArgs[] = [];
  const namespaces: string[] = [];
  const step = vi.fn(async (name: string, stepInput: unknown) => {
    calls.push({ name, input: stepInput });
    return name === "decisions" ? decisions() : undefined;
  });
  return {
    stop,
    turn,
    calls,
    agentArgs,
    namespaces,
    run: () =>
      durableTurn(input, {
        runId: "wrun",
        // SAFETY: the map holds a hook for each token the turn asks for.
        createHook: <T>({ token }: { token: string }) =>
          tokens.get(token) as DurableHook<T>,
        getWritable: ({ namespace }) => {
          namespaces.push(namespace);
          return new WritableStream<ModelCallStreamPart>();
        },
        agent: (args) => {
          agentArgs.push(args);
          return agent(args);
        },
        // SAFETY: the fake answers `decisions` with decisions and the rest with nothing.
        step: step as unknown as DurableStep,
      }),
  };
}

describe("durableTurn", () => {
  it("saves and releases one segment when no approval is asked", async () => {
    const h = harness(async (args) => ({
      messages: [...args.messages, answer("Done.")],
      steps: [
        {
          sources: [
            { type: "source", sourceType: "url", id: "s", url: "https://a.b" },
          ],
          providerMetadata: { gateway: { generationId: "gen_1" } },
        },
      ],
      totalUsage: usage,
    }));
    await expect(h.run()).resolves.toEqual({
      status: "done",
      messageId: "m1",
      segments: 1,
    });
    expect(h.namespaces).toEqual(["s1"]);
    expect(h.agentArgs[0]).toMatchObject({
      chatId: "c1",
      runId: "run1",
      messages: [user],
      model: "openai/gpt-5",
      providerOptions: { gateway: { user: "user" } },
    });
    expect(h.calls.map((call) => call.name)).toEqual(["save", "release"]);
    const save = h.calls[0]?.input as DurableSaveInput;
    expect(save).toMatchObject({
      chatId: "c1",
      parentId: "u1",
      runId: "run1",
      status: "complete",
    });
    expect(save.message.id).toBe("m1");
    expect(save.message.parts).toContainEqual(
      expect.objectContaining({ type: "text", text: "Done." }),
    );
    expect(save.message.parts).toContainEqual(
      expect.objectContaining({ type: "source", url: "https://a.b" }),
    );
    expect(h.calls[1]?.input).toMatchObject({
      streamId: "s1",
      status: "done",
      usage: { inputTokens: 5, outputTokens: 2, generationId: "gen_1" },
    });
  });

  it("waits for the approvals and continues in a new segment", async () => {
    let pass = 0;
    const h = harness(
      async (args) => {
        pass += 1;
        return pass === 1
          ? { messages: [...args.messages, asking], steps: [] }
          : {
              messages: [
                ...args.messages.filter((m) => m.role !== "tool"),
                {
                  role: "tool",
                  content: [
                    {
                      type: "tool-result",
                      toolCallId: "t1",
                      toolName: "remove",
                      output: { type: "json", value: { removed: true } },
                    },
                  ],
                },
                answer("Removed."),
              ],
              steps: [],
            };
      },
      () => [{ approvalId: "approval-t1", approved: true, reason: "ok" }],
    );
    const running = h.run();
    await vi.waitFor(() => {
      expect(h.calls).toHaveLength(3);
    });
    expect(h.calls.map((call) => call.name)).toEqual([
      "save",
      "approvals",
      "release",
    ]);
    expect(h.calls[1]?.input).toEqual({
      chatId: "c1",
      runId: "run1",
      messageId: "m1",
      requests: [
        {
          approvalId: "approval-t1",
          toolCallId: "t1",
          toolName: "remove",
          input: { path: "a.txt" },
          signature: "sig",
        },
      ],
    });
    const waiting = (h.calls[0]!.input as DurableSaveInput).message.parts;
    expect(waiting).toContainEqual(
      expect.objectContaining({
        type: "tool-approval",
        approvalId: "approval-t1",
        state: "requested",
      }),
    );

    h.turn.push({ streamId: "s2", runId: "run2" });
    await expect(running).resolves.toEqual({
      status: "done",
      messageId: "m1",
      segments: 2,
    });
    expect(h.namespaces).toEqual(["s1", "s2"]);
    expect(h.agentArgs[1]?.runId).toBe("run2");
    expect(h.agentArgs[1]?.messages.at(-1)).toEqual({
      role: "tool",
      content: [
        {
          type: "tool-approval-response",
          approvalId: "approval-t1",
          approved: true,
          reason: "ok",
        },
      ],
    });
    expect(h.calls.map((call) => call.name)).toEqual([
      "save",
      "approvals",
      "release",
      "decisions",
      "save",
      "release",
    ]);
    const saved = (h.calls[4]!.input as DurableSaveInput).message.parts;
    expect(h.calls[4]?.input).toMatchObject({ runId: "run2" });
    expect(saved).toContainEqual(
      expect.objectContaining({
        type: "tool-approval",
        approvalId: "approval-t1",
        state: "approved",
      }),
    );
    expect(saved).toContainEqual(
      expect.objectContaining({ type: "text", text: "Removed." }),
    );
    expect(h.calls[5]?.input).toMatchObject({ streamId: "s2" });
  });

  it("keeps waiting while decisions are missing", async () => {
    let reads = 0;
    const h = harness(
      async (args) => ({ messages: [...args.messages, asking], steps: [] }),
      () => {
        reads += 1;
        return reads === 1
          ? []
          : [{ approvalId: "approval-t1", approved: false }];
      },
    );
    const running = h.run();
    await vi.waitFor(() => {
      expect(h.calls).toHaveLength(3);
    });
    h.turn.push({ streamId: "s2", runId: "run2" });
    await vi.waitFor(() => {
      expect(reads).toBe(1);
    });
    h.stop.push({});
    await expect(running).resolves.toMatchObject({ status: "stopped" });
    expect(reads).toBe(1);
  });

  it("stops while it waits on approvals", async () => {
    const h = harness(async (args) => ({
      messages: [...args.messages, asking],
      steps: [],
    }));
    const running = h.run();
    await vi.waitFor(() => {
      expect(h.calls).toHaveLength(3);
    });
    h.stop.push({});
    await expect(running).resolves.toEqual({
      status: "stopped",
      messageId: "m1",
      segments: 1,
    });
  });

  it("aborts the agent through the stop hook", async () => {
    const h = harness(
      (args) =>
        new Promise((_, reject) => {
          args.abortSignal.addEventListener("abort", () => {
            reject(new Error("aborted"));
          });
        }),
    );
    const running = h.run();
    await vi.waitFor(() => {
      expect(h.agentArgs).toHaveLength(1);
    });
    h.stop.push({});
    await expect(running).resolves.toMatchObject({ status: "stopped" });
    expect(h.calls[0]?.input).toMatchObject({ status: "aborted" });
    expect(h.calls[1]?.input).toMatchObject({ status: "stopped" });
  });

  it("saves an error and releases the segment when the agent fails", async () => {
    const h = harness(async () => {
      throw new Error("model down");
    });
    await expect(h.run()).resolves.toMatchObject({ status: "error" });
    expect(h.calls[0]?.input).toMatchObject({ status: "error" });
    expect(h.calls[1]?.input).toMatchObject({
      status: "error",
      error: "model down",
    });
  });

  it("reports a thrown non-error", async () => {
    const h = harness(() => Promise.reject("boom"));
    await h.run();
    expect(h.calls[1]?.input).toMatchObject({ error: "boom" });
  });
});
