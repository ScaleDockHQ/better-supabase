import type { UIMessageChunk } from "ai";

import { Temporal } from "temporal-polyfill";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { AssistantTurn } from "../../../src/ai-sdk/chat/index.ts";
import type {
  AiChat,
  AiChatRecord,
  AiRun,
  AiRuns,
  AiToolApproval,
} from "../../../src/blocks/ai-chat/index.ts";
import type { DbError } from "../../../src/core/errors.ts";

import {
  type DurableChatContext,
  durableChat,
  WORKFLOW_RUN_ID_HEADER,
} from "../../../src/ai-sdk/workflow/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";
import { redisStreamStore } from "../../../src/streams/redis/index.ts";
import { fakeRedis } from "../../streams/fakes.ts";
import { record } from "../chat/fakes.ts";

const api = vi.hoisted(() => ({
  start: vi.fn(),
  getRun: vi.fn(),
  resumeHook: vi.fn(),
}));

vi.mock("workflow/api", () => api);

vi.mock("@ai-sdk/workflow", () => ({
  createModelCallToUIChunkTransform: () => new TransformStream(),
  async *normalizeUIMessageStreamParts(source: AsyncIterable<unknown>) {
    yield* source;
  },
}));

const NOW = Temporal.Instant.from("2030-01-01T00:00:00Z");
const result = <T>(value: T) => AsyncResult.from(async () => ok(value));
const failure = (error: DbError) => AsyncResult.from(async () => err(error));

const CHUNKS: UIMessageChunk[] = [
  { type: "start" },
  { type: "text-start", id: "t" },
  { type: "text-delta", id: "t", delta: "Hi" },
  { type: "text-end", id: "t" },
  { type: "finish" },
];

function readable(chunks: readonly unknown[] = CHUNKS): ReadableStream {
  return new ReadableStream({
    start(controller) {
      for (const chunk of chunks) controller.enqueue(chunk);
      controller.close();
    },
  });
}

function run(over: Partial<AiRun> = {}): AiRun {
  return {
    id: "run1",
    chatId: "c1",
    ownerId: "user",
    assistantMessageId: "m1",
    streamId: "s1",
    engine: "workflow",
    externalRunId: "wrun",
    model: "openai/gpt-5",
    status: "running",
    usage: {},
    costMicroUsd: undefined,
    error: undefined,
    startedAt: NOW,
    endedAt: undefined,
    ...over,
  };
}

function approval(over: Partial<AiToolApproval> = {}): AiToolApproval {
  return {
    approvalId: "a1",
    chatId: "c1",
    runId: "run1",
    messageId: "m1",
    tool: "remove",
    toolCallId: "t1",
    input: {},
    decision: "approved",
    reason: undefined,
    signature: undefined,
    decidedBy: "user",
    decidedAt: NOW,
    createdAt: NOW,
    ...over,
  };
}

interface Setup {
  readonly chat?: AiChatRecord | DbError;
  readonly claimed?: boolean;
  readonly runs?: readonly AiRun[];
  readonly approvals?: readonly AiToolApproval[];
  readonly decided?: AiToolApproval | DbError;
  readonly stopped?: { streamId: string; runId: string };
  readonly turn?: Partial<AssistantTurn> | Response;
  readonly attach?: DbError;
}

function setup(options: Setup = {}) {
  const calls: { name: string; args: unknown[] }[] = [];
  const log =
    <T>(name: string, value: () => ReturnType<typeof result<T>>) =>
    (...args: unknown[]) => {
      calls.push({ name, args });
      return value();
    };
  const chat = options.chat ?? record("c1", { model: "openai/gpt-5" });
  const runs = options.runs ?? [run()];
  const chats = {
    chats: {
      get: log("chats.get", () =>
        "kind" in chat ? failure(chat) : result(chat),
      ),
    },
    runs: {
      claim: log("claim", () =>
        result(
          options.claimed === false
            ? { claimed: false, streamId: "other", runId: undefined }
            : { claimed: true, streamId: "s", runId: "run2" },
        ),
      ),
      release: log("release", () => result(true)),
      stop: log("stop", () => result(options.stopped)),
    },
    approvals: {
      decide: log("decide", () => {
        const decided = options.decided ?? approval();
        return "kind" in decided ? failure(decided) : result(decided);
      }),
      list: log("list", () => result(options.approvals ?? [approval()])),
    },
  };
  const aiRuns = {
    get: log("runs.get", () => {
      const found = runs[0];
      return found ? result(found) : failure(dbError("not_found", "none"));
    }),
    list: log("runs.list", () => result(runs)),
    attach: log("attach", () =>
      options.attach === undefined ? result(true) : failure(options.attach),
    ),
  };
  const pending: Promise<unknown>[] = [];
  const context: DurableChatContext = {
    // SAFETY: the fakes implement the calls `durableChat` makes.
    chats: chats as unknown as AiChat,
    // SAFETY: as above.
    runs: aiRuns as unknown as AiRuns,
    userId: "user",
    organizationId: "org",
    waitUntil: (promise) => pending.push(promise),
  };
  const turn: AssistantTurn | Response =
    options.turn instanceof Response
      ? options.turn
      : {
          chat: record("c1"),
          model: "openai/gpt-5",
          parentId: "u1",
          uiMessages: [],
          messages: [{ role: "user", content: "Hi" }],
          providerOptions: { gateway: {} },
          ...options.turn,
        };
  const prepare = vi.fn(async () => turn);
  const { client } = fakeRedis();
  const streams = redisStreamStore({ client });
  const workflow = vi.fn(async () => undefined);
  let ids = 0;
  const durable = durableChat({
    assistant: { prepare },
    workflow,
    streams,
    streamTtl: 60,
    generateId: () => `id${++ids}`,
  });
  return { durable, context, calls, prepare, pending, streams, workflow };
}

const post = (body: unknown): Request =>
  new Request("https://app.test/api/chat", {
    method: "POST",
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

const names = (calls: { name: string }[]) => calls.map((call) => call.name);

afterEach(() => {
  vi.resetAllMocks();
});

describe("durableChat respond", () => {
  it("starts the turn's workflow and streams its first segment", async () => {
    api.start.mockResolvedValue({ runId: "wrun" });
    api.getRun.mockReturnValue({ getReadable: () => readable() });
    const s = setup();
    const response = await s.durable.respond(post({ id: "c1" }), s.context);
    expect(response.status).toBe(200);
    expect(response.headers.get(WORKFLOW_RUN_ID_HEADER)).toBe("wrun");
    const body = await response.text();
    expect(body).toContain('{"type":"start","messageId":"id2"}');
    expect(body).toContain('"delta":"Hi"');
    await Promise.all(s.pending);

    expect(s.calls.find((call) => call.name === "claim")?.args).toEqual([
      "c1",
      "id1",
      { model: "openai/gpt-5", messageId: "id2", engine: "workflow" },
    ]);
    expect(api.start).toHaveBeenCalledWith(
      s.workflow,
      [
        expect.objectContaining({
          chatId: "c1",
          organizationId: "org",
          userId: "user",
          messageId: "id2",
          parentId: "u1",
          runId: "run2",
          streamId: "id1",
        }),
      ],
      {
        attributes: {
          "bs.tenant": "org",
          "bs.actor": "user",
          "bs.key": "ai-chat:c1",
        },
      },
    );
    expect(s.calls.find((call) => call.name === "attach")?.args).toEqual([
      "run2",
      "wrun",
    ]);
    expect(api.getRun).toHaveBeenCalledWith("wrun");
    const status = await s.streams.status("id1").orThrow();
    expect(status).toBeDefined();
  });

  it("returns the assistant's own response", async () => {
    const s = setup({ turn: new Response(null, { status: 402 }) });
    const response = await s.durable.respond(post({ id: "c1" }), s.context);
    expect(response.status).toBe(402);
  });

  it("answers busy when another answer runs", async () => {
    const s = setup({ claimed: false });
    const response = await s.durable.respond(post({ id: "c1" }), s.context);
    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ code: "AI_CHAT_BUSY" });
  });

  it("releases the claim when the workflow does not start", async () => {
    api.start.mockRejectedValue(new Error("no world"));
    const s = setup();
    const response = await s.durable.respond(post("not json"), s.context);
    expect(response.status).toBe(500);
    expect(await response.json()).toMatchObject({
      code: "AI_CHAT_RUN_FAILED",
    });
    expect(s.calls.find((call) => call.name === "release")?.args).toEqual([
      "c1",
      "id1",
      { status: "error", error: "Error: no world" },
    ]);
  });

  it("cancels the run and releases the claim when the run can't be attached", async () => {
    api.start.mockResolvedValue({ runId: "wrun" });
    const cancel = vi.fn(async () => {
      throw new Error("gone");
    });
    api.getRun.mockReturnValue({ cancel });
    const s = setup({ attach: dbError("network", "offline") });
    const response = await s.durable.respond(post({ id: "c1" }), s.context);
    expect(response.status).toBe(503);
    expect(cancel).toHaveBeenCalledOnce();
    expect(s.calls.find((call) => call.name === "release")?.args).toEqual([
      "c1",
      "id1",
      { status: "error", error: "offline" },
    ]);
  });

  it("decides approvals and continues the waiting turn", async () => {
    api.resumeHook.mockResolvedValue(undefined);
    api.getRun.mockReturnValue({ getReadable: () => readable() });
    const s = setup();
    const response = await s.durable.respond(
      post({
        id: "c1",
        approvals: [{ approvalId: "a1", approved: true, reason: "ok" }],
      }),
      s.context,
    );
    expect(response.status).toBe(200);
    expect(response.headers.get(WORKFLOW_RUN_ID_HEADER)).toBe("wrun");
    expect(await response.text()).toContain('"messageId":"m1"');
    expect(s.calls.find((call) => call.name === "decide")?.args).toEqual([
      "a1",
      true,
      "ok",
    ]);
    expect(s.calls.find((call) => call.name === "claim")?.args).toEqual([
      "c1",
      "id1",
      {
        engine: "workflow",
        externalRunId: "wrun",
        model: "openai/gpt-5",
        messageId: "m1",
      },
    ]);
    expect(api.resumeHook).toHaveBeenCalledWith("ai-chat-turn:wrun", {
      streamId: "id1",
      runId: "run2",
    });
  });

  it("waits while other approvals of the answer are pending", async () => {
    const s = setup({
      approvals: [
        approval(),
        approval({ approvalId: "a2", decision: "pending" }),
      ],
    });
    const response = await s.durable.respond(
      post({ id: "c1", approvals: [{ approvalId: "a1", approved: true }] }),
      s.context,
    );
    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({
      code: "AI_APPROVALS_PENDING",
    });
    expect(names(s.calls)).not.toContain("claim");
  });

  it.each([
    { id: "c1", approvals: [] },
    { id: "c1", approvals: [{ approvalId: 1 }] },
    { approvals: [{ approvalId: "a1", approved: true }] },
  ])("rejects a malformed decision body %#", async (body) => {
    const s = setup();
    const response = await s.durable.respond(post(body), s.context);
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({
      code: "AI_CHAT_BAD_REQUEST",
    });
    expect(names(s.calls)).not.toContain("decide");
  });

  it("rejects approvals of another chat", async () => {
    const s = setup({ decided: approval({ chatId: "c2" }) });
    const response = await s.durable.respond(
      post({ id: "c1", approvals: [{ approvalId: "a1", approved: false }] }),
      s.context,
    );
    expect(response.status).toBe(400);
  });

  it.each([
    ["no run", approval({ runId: undefined }), [run()]],
    ["an ai-sdk run", approval(), [run({ engine: "ai-sdk" })]],
    ["no workflow run id", approval(), [run({ externalRunId: undefined })]],
  ])("answers not durable for %s", async (_, decided, runs) => {
    const s = setup({ decided, runs });
    const response = await s.durable.respond(
      post({ id: "c1", approvals: [{ approvalId: "a1", approved: true }] }),
      s.context,
    );
    expect(await response.json()).toMatchObject({
      code: "AI_CHAT_NOT_DURABLE",
    });
  });

  it("passes database errors on", async () => {
    const forbidden = dbError("forbidden", "not yours");
    for (const options of [
      { decided: forbidden },
      { chat: forbidden },
      { runs: [] },
    ]) {
      const s = setup(options);
      const response = await s.durable.respond(
        post({ id: "c1", approvals: [{ approvalId: "a1", approved: true }] }),
        s.context,
      );
      expect(response.status).toBeGreaterThanOrEqual(400);
    }
  });

  it("releases the new segment when the turn no longer waits", async () => {
    api.resumeHook.mockRejectedValue(new Error("hook gone"));
    const s = setup();
    const response = await s.durable.respond(
      post({ id: "c1", approvals: [{ approvalId: "a1", approved: true }] }),
      s.context,
    );
    expect(await response.json()).toMatchObject({
      code: "AI_CHAT_NOT_WAITING",
    });
    expect(s.calls.find((call) => call.name === "release")?.args[2]).toEqual({
      status: "error",
      error: "Error: hook gone",
    });
  });

  it("answers busy when a segment is already claimed", async () => {
    const s = setup({ claimed: false });
    const response = await s.durable.respond(
      post({ id: "c1", approvals: [{ approvalId: "a1", approved: true }] }),
      s.context,
    );
    expect(await response.json()).toMatchObject({ code: "AI_CHAT_BUSY" });
  });
});

describe("durableChat resume", () => {
  it("reads the running segment from the World", async () => {
    api.getRun.mockReturnValue({ getReadable: () => readable() });
    const s = setup({ chat: record("c1", { activeRunId: "run1" }) });
    const response = await s.durable.resume("c1", s.context, {
      startIndex: 2.7,
    });
    expect(response.headers.get(WORKFLOW_RUN_ID_HEADER)).toBe("wrun");
    expect(await response.text()).toContain('"delta":"Hi"');
    expect(names(s.calls)).toContain("runs.get");
  });

  it("falls back to the stream store when the World fails", async () => {
    api.start.mockResolvedValue({ runId: "wrun" });
    api.getRun.mockReturnValue({ getReadable: () => readable() });
    const s = setup({ runs: [run({ streamId: "id1" })] });
    const live = await (
      await s.durable.respond(post({ id: "c1" }), s.context)
    ).text();
    await Promise.all(s.pending);
    api.getRun.mockReturnValue({
      getReadable: () =>
        new ReadableStream({
          pull() {
            throw new Error("world down");
          },
        }),
    });
    const fromStore = await s.durable.resume("c1", s.context, {
      signal: new AbortController().signal,
    });
    expect(fromStore.status).toBe(200);
    expect(await fromStore.text()).toBe(live);

    api.getRun.mockImplementation(() => {
      throw new Error("no run");
    });
    const again = await s.durable.resume("c1", s.context);
    expect(await again.text()).toBe(live);
  });

  it("cancels the World's stream when the request aborts", async () => {
    let cancelled: unknown;
    api.getRun.mockReturnValue({
      getReadable: () =>
        new ReadableStream({
          start(controller) {
            controller.enqueue(CHUNKS[0]);
          },
          cancel(reason) {
            cancelled = reason;
          },
        }),
    });
    const s = setup({ chat: record("c1", { activeRunId: "run1" }) });
    const abort = new AbortController();
    const response = await s.durable.resume("c1", s.context, {
      signal: abort.signal,
    });
    const reader = response.body!.getReader();
    await reader.read();
    abort.abort("client left");
    await vi.waitFor(() => {
      expect(cancelled).toBe("client left");
    });
    let reads = 0;
    while (!(await reader.read()).done) reads += 1;
    expect(reads).toBeLessThan(3);
  });

  it("answers 204 when the chat has no durable segment", async () => {
    expect(
      (
        await setup({ chat: dbError("not_found", "no chat") }).durable.resume(
          "c1",
          setup().context,
        )
      ).status,
    ).toBe(204);
    const none = setup({ runs: [] });
    expect((await none.durable.resume("c1", none.context)).status).toBe(204);
    const noStream = setup({ runs: [run({ streamId: undefined })] });
    expect((await noStream.durable.resume("c1", noStream.context)).status).toBe(
      204,
    );
    const plain = setup({ runs: [run({ engine: "ai-sdk" })] });
    expect((await plain.durable.resume("c1", plain.context)).status).toBe(204);
  });

  it("passes database errors on", async () => {
    const s = setup({ chat: dbError("forbidden", "not yours") });
    expect((await s.durable.resume("c1", s.context)).status).toBe(403);
    const active = setup({
      chat: record("c1", { activeRunId: "r" }),
      runs: [],
    });
    expect((await active.durable.resume("c1", active.context)).status).toBe(
      404,
    );
  });
});

describe("durableChat stop", () => {
  it("stops the turn through its stop hook", async () => {
    api.resumeHook.mockResolvedValue(undefined);
    const s = setup({ stopped: { streamId: "s1", runId: "run1" } });
    expect((await s.durable.stop("c1", s.context)).status).toBe(204);
    expect(api.resumeHook).toHaveBeenCalledWith("ai-chat-stop:wrun", {});
    expect(names(s.calls)).not.toContain("release");
  });

  it("cancels the run and releases the segment without a hook", async () => {
    api.resumeHook.mockRejectedValue(new Error("hook gone"));
    const cancel = vi.fn(async () => undefined);
    api.getRun.mockReturnValue({ cancel });
    const s = setup({ stopped: { streamId: "s1", runId: "run1" } });
    expect((await s.durable.stop("c1", s.context)).status).toBe(204);
    expect(cancel).toHaveBeenCalledOnce();
    expect(s.calls.find((call) => call.name === "release")?.args).toEqual([
      "c1",
      "s1",
      { status: "stopped" },
    ]);
  });

  it("releases the segment and answers 500 when the run can't be cancelled", async () => {
    api.resumeHook.mockRejectedValue(new Error("hook gone"));
    api.getRun.mockReturnValue({
      cancel: vi.fn(async () => {
        throw new Error("world down");
      }),
    });
    const s = setup({ stopped: { streamId: "s1", runId: "run1" } });
    const response = await s.durable.stop("c1", s.context);
    expect(response.status).toBe(500);
    expect(await response.json()).toMatchObject({
      code: "AI_CHAT_STOP_FAILED",
    });
    expect(s.calls.find((call) => call.name === "release")?.args).toEqual([
      "c1",
      "s1",
      { status: "stopped" },
    ]);
  });

  it("does nothing when no durable answer runs", async () => {
    const idle = setup();
    expect((await idle.durable.stop("c1", idle.context)).status).toBe(204);
    const plain = setup({
      stopped: { streamId: "s1", runId: "run1" },
      runs: [run({ externalRunId: undefined })],
    });
    expect((await plain.durable.stop("c1", plain.context)).status).toBe(204);
    expect(api.resumeHook).not.toHaveBeenCalled();
    const missing = setup({
      stopped: { streamId: "s1", runId: "run1" },
      runs: [],
    });
    expect((await missing.durable.stop("c1", missing.context)).status).toBe(
      404,
    );
  });
});

describe("durableChat decide", () => {
  it("continues the turn once nothing is pending", async () => {
    api.resumeHook.mockResolvedValue(undefined);
    const s = setup();
    const response = await s.durable.decide(
      "c1",
      [{ approvalId: "a1", approved: true }],
      s.context,
    );
    expect(await response.json()).toEqual({ continued: true, streamId: "id1" });
  });

  it("reports a turn that still waits", async () => {
    const s = setup({
      approvals: [approval({ approvalId: "a2", decision: "pending" })],
    });
    const response = await s.durable.decide(
      "c1",
      [{ approvalId: "a1", approved: false, reason: "no" }],
      s.context,
    );
    expect(await response.json()).toEqual({ continued: false });
  });

  it("rejects an empty decision list and passes errors on", async () => {
    const s = setup({ decided: dbError("forbidden", "not yours") });
    expect((await s.durable.decide("c1", [], s.context)).status).toBe(400);
    expect(
      (
        await s.durable.decide(
          "c1",
          [{ approvalId: "a1", approved: true }],
          s.context,
        )
      ).status,
    ).toBe(403);
  });
});
