import { streamText, type UIMessage } from "ai";
import { convertArrayToReadableStream, MockLanguageModelV4 } from "ai/test";
import { Temporal } from "temporal-polyfill";
import { describe, expect, it, vi } from "vitest";

import type {
  AiChat,
  AiChatRecord,
  AiMessage,
  AiStoredMessage,
} from "../../../src/blocks/ai-chat/index.ts";
import type { DbError } from "../../../src/core/errors.ts";

import {
  type AssistantContext,
  type AssistantOptions,
  createAssistant,
} from "../../../src/ai-sdk/chat/index.ts";
import { AI_SDK_UI_FORMAT } from "../../../src/ai-sdk/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";
import { redisStreamStore } from "../../../src/streams/redis/index.ts";
import { fakeRedis } from "../../streams/fakes.ts";

const NOW = Temporal.Instant.from("2030-01-01T00:00:00Z");
const result = <T>(value: T) => AsyncResult.from(async () => ok(value));
const failure = (error: DbError) => AsyncResult.from(async () => err(error));

function record(id: string, over: Partial<AiChatRecord> = {}): AiChatRecord {
  return {
    id,
    organizationId: "org",
    ownerId: "user",
    projectId: undefined,
    agentId: undefined,
    title: "",
    model: undefined,
    visibility: "private",
    pinned: false,
    archivedAt: undefined,
    temporary: false,
    expiresAt: undefined,
    leafId: undefined,
    activeStreamId: undefined,
    activeRunId: undefined,
    lastMessageAt: NOW,
    createdAt: NOW,
    updatedAt: NOW,
    ...over,
  };
}

interface FakeOptions {
  readonly models?: readonly string[];
  readonly claimed?: boolean;
  readonly getError?: DbError;
}

function fakeChats(options: FakeOptions = {}) {
  const chats = new Map<string, AiChatRecord>();
  const tree: AiStoredMessage[] = [];
  const store = (
    message: AiMessage,
    parentId: string | undefined,
    extra: Partial<AiStoredMessage> = {},
  ) => {
    tree.push({
      ...message,
      parentId,
      format: "canonical",
      native: undefined,
      model: undefined,
      status: "complete",
      createdAt: NOW,
      siblingCount: 1,
      siblingIndex: 0,
      ...extra,
    });
  };
  const released: unknown[] = [];
  const saved: unknown[] = [];
  const moderated: unknown[] = [];
  const stops: string[] = [];
  const api = {
    chats: {
      get: (id: string) => {
        if (options.getError) return failure(options.getError);
        const chat = chats.get(id);
        return chat ? result(chat) : failure(dbError("not_found", "no chat"));
      },
      create: (
        organizationId: string,
        input: { id: string; model?: string },
      ) => {
        const chat = record(input.id, {
          organizationId,
          model: input.model,
        });
        chats.set(chat.id, chat);
        return result(chat);
      },
    },
    models: {
      allowed: () => result((options.models ?? []).map((id) => ({ id }))),
    },
    moderation: {
      record: (event: unknown) => {
        moderated.push(event);
        return result(event);
      },
    },
    messages: {
      appendUser: (
        chatId: string,
        message: AiMessage,
        opts: { trigger?: string; messageId?: string } = {},
      ) => {
        if (opts.trigger === "regenerate-message")
          return result({
            messageId: tree.find((m) => m.role === "user")?.id ?? "",
            parentId: undefined,
            created: false,
          });
        const chat = chats.get(chatId);
        store(message, chat?.leafId);
        if (chat) chats.set(chatId, { ...chat, leafId: message.id });
        return result({
          messageId: message.id,
          parentId: chat?.leafId,
          created: true,
        });
      },
      path: () => result([...tree]),
      saveAssistant: (
        chatId: string,
        message: AiMessage,
        opts: { parentId: string; native?: unknown; format?: string },
      ) => {
        saved.push({ chatId, message, opts });
        store(message, opts.parentId, {
          format: opts.format ?? "canonical",
          native: opts.native,
        });
        return result({
          messageId: message.id,
          parentId: opts.parentId,
          created: true,
        });
      },
    },
    runs: {
      claim: (chatId: string, streamId: string) => {
        if (options.claimed === false)
          return result({
            claimed: false,
            streamId: "other",
            runId: undefined,
          });
        const chat = chats.get(chatId);
        if (chat)
          chats.set(chatId, {
            ...chat,
            activeStreamId: streamId,
            activeRunId: "run1",
          });
        return result({ claimed: true, streamId, runId: "run1" });
      },
      release: (chatId: string, streamId: string, opts: unknown) => {
        released.push({ chatId, streamId, opts });
        return result(true);
      },
      stop: (chatId: string) => {
        stops.push(chatId);
        return chatId === "missing"
          ? failure(dbError("forbidden", "not yours"))
          : result(undefined);
      },
    },
  };
  return {
    // The fake implements the calls the assistant makes.
    chats: api as unknown as AiChat,
    raw: chats,
    tree,
    released,
    saved,
    moderated,
    stops,
  };
}

function mockModel(text = "Hello there") {
  return new MockLanguageModelV4({
    doStream: async () => ({
      stream: convertArrayToReadableStream([
        { type: "stream-start", warnings: [] },
        { type: "text-start", id: "t" },
        { type: "text-delta", id: "t", delta: text },
        { type: "text-end", id: "t" },
        {
          type: "finish",
          finishReason: { unified: "stop", raw: "stop" },
          usage: {
            inputTokens: { total: 7, noCache: 7, cacheRead: 0, cacheWrite: 0 },
            outputTokens: { total: 3, text: 3, reasoning: 0 },
          },
          providerMetadata: { gateway: { generationId: "gen_1" } },
        },
      ]),
    }),
  });
}

const userMessage = (id = "u1", text = "Hi"): UIMessage => ({
  id,
  role: "user",
  parts: [{ type: "text", text }],
});

const post = (body: unknown) =>
  new Request("https://app.test/api/chat", {
    method: "POST",
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

function setup(
  over: Partial<AssistantOptions> = {},
  fake: ReturnType<typeof fakeChats> = fakeChats(),
) {
  const { client } = fakeRedis();
  const streams = redisStreamStore({ client });
  const pending: Promise<unknown>[] = [];
  const context: AssistantContext = {
    chats: fake.chats,
    userId: "user",
    organizationId: "org",
    waitUntil: (promise) => pending.push(promise),
  };
  let ids = 0;
  const run = vi.fn<AssistantOptions["run"]>((args) =>
    streamText({
      model: mockModel(),
      messages: args.messages,
      abortSignal: args.abortSignal,
      providerOptions: args.providerOptions,
    }),
  );
  const assistant = createAssistant({
    streams,
    run,
    defaultModel: "openai/gpt-5",
    generateId: () => `id${++ids}`,
    ...over,
  });
  return { assistant, context, fake, pending, streams, run };
}

describe("createAssistant", () => {
  it("stores the turn, streams the answer and records its usage", async () => {
    const enqueueCostBackfill = vi.fn(async () => undefined);
    const onFinish = vi.fn();
    const { assistant, context, fake, pending, run } = setup({
      enqueueCostBackfill,
      onFinish,
    });
    const response = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("x-vercel-ai-ui-message-stream")).toBe("v1");
    const body = await response.text();
    expect(body).toContain('"delta":"Hello there"');
    expect(body).toContain("data: [DONE]");
    await Promise.all(pending);

    expect(run).toHaveBeenCalledOnce();
    const args = run.mock.calls[0]?.[0];
    expect(args?.model).toBe("openai/gpt-5");
    expect(args?.providerOptions).toEqual({
      gateway: {
        user: "user",
        tags: ["org:org", "chat:c1", "feature:chat"],
      },
    });
    expect(args?.messages).toEqual([
      { role: "user", content: [{ type: "text", text: "Hi" }] },
    ]);
    expect(fake.saved).toEqual([
      {
        chatId: "c1",
        message: {
          id: "id2",
          role: "assistant",
          parts: [
            { type: "step", boundary: "start" },
            { type: "text", text: "Hello there", state: "done" },
          ],
        },
        opts: expect.objectContaining({
          parentId: "u1",
          status: "complete",
          model: "openai/gpt-5",
          format: AI_SDK_UI_FORMAT,
          runId: "run1",
        }),
      },
    ]);
    expect(fake.released).toEqual([
      {
        chatId: "c1",
        streamId: "id1",
        opts: {
          status: "done",
          usage: {
            inputTokens: 7,
            outputTokens: 3,
            totalTokens: 10,
            cachedInputTokens: 0,
            reasoningTokens: 0,
          },
          generationId: "gen_1",
        },
      },
    ]);
    expect(enqueueCostBackfill).toHaveBeenCalledWith({
      generationId: "gen_1",
      organizationId: "org",
    });
    expect(onFinish).toHaveBeenCalledWith(
      expect.objectContaining({ status: "done", model: "openai/gpt-5" }),
    );
  });

  it("replays the stored stream and answers 204 when nothing runs", async () => {
    const { assistant, context, fake, pending } = setup();
    const first = await assistant.respond(
      post({ id: "c1", messages: [userMessage()] }),
      context,
    );
    const live = await first.text();
    await Promise.all(pending);
    const replay = await assistant.resume("c1", context);
    expect(replay.status).toBe(200);
    expect(await replay.text()).toBe(live);
    const chat = fake.raw.get("c1");
    if (chat) fake.raw.set("c1", { ...chat, activeStreamId: undefined });
    expect((await assistant.resume("c1", context)).status).toBe(204);
    expect((await assistant.resume("nope", context)).status).toBe(204);
    const done = await assistant.resume("c1", context, { fromIdx: 0 });
    expect(done.status).toBe(204);
  });

  it("resumes past the end with 204 and passes the signal", async () => {
    const { assistant, context, pending } = setup();
    const first = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    await first.text();
    await Promise.all(pending);
    const after = await assistant.resume("c1", context, {
      fromIdx: 10_000,
      signal: new AbortController().signal,
    });
    expect(after.status).toBe(204);
  });

  it("sends the history it has, with the stored native answer", async () => {
    const { assistant, context, fake, pending, run } = setup();
    await (
      await assistant.respond(
        post({ id: "c1", message: userMessage() }),
        context,
      )
    ).text();
    await Promise.all(pending);
    await (
      await assistant.respond(
        post({ id: "c1", message: userMessage("u2", "Again") }),
        context,
      )
    ).text();
    await Promise.all(pending);
    expect(run.mock.calls[1]?.[0].uiMessages.map((m) => m.id)).toEqual([
      "u1",
      "id2",
      "u2",
    ]);
    expect(fake.tree.at(-1)?.native).toMatchObject({ id: "id4" });
  });

  it("regenerates from the user's message", async () => {
    const { assistant, context, fake, pending } = setup();
    await (
      await assistant.respond(
        post({ id: "c1", message: userMessage() }),
        context,
      )
    ).text();
    await Promise.all(pending);
    const response = await assistant.respond(
      post({
        id: "c1",
        message: userMessage(),
        trigger: "regenerate-message",
        messageId: "id2",
      }),
      context,
    );
    await response.text();
    await Promise.all(pending);
    expect(fake.saved).toHaveLength(2);
  });

  it("rejects bad requests", async () => {
    const { assistant, context } = setup();
    const status = async (body: unknown) =>
      (await assistant.respond(post(body), context)).status;
    expect(await status("{")).toBe(400);
    expect(await status([])).toBe(400);
    expect(await status({ id: "" })).toBe(400);
    expect(
      await status({
        id: "c",
        message: { id: "a", role: "assistant", parts: [] },
      }),
    ).toBe(400);
    expect(
      await status({ id: "c", message: userMessage(), trigger: "other" }),
    ).toBe(400);
  });

  it("checks the model against the catalog", async () => {
    const fake = fakeChats({ models: ["anthropic/claude", "openai/gpt-5"] });
    const { assistant, context, pending, run } = setup({}, fake);
    const refused = await assistant.respond(
      post({ id: "c1", message: userMessage(), model: "x/unknown" }),
      context,
    );
    expect(refused.status).toBe(403);
    await (
      await assistant.respond(
        post({ id: "c2", message: userMessage(), model: "anthropic/claude" }),
        context,
      )
    ).text();
    await Promise.all(pending);
    expect(run.mock.calls[0]?.[0].model).toBe("anthropic/claude");

    const other = fakeChats({ models: ["anthropic/claude"] });
    const second = setup({}, other);
    await (
      await second.assistant.respond(
        post({ id: "c3", message: userMessage() }),
        second.context,
      )
    ).text();
    expect(second.run.mock.calls[0]?.[0].model).toBe("anthropic/claude");
  });

  it("uses the chat's model when it is allowed", async () => {
    const fake = fakeChats({ models: ["a/one", "a/two"] });
    fake.raw.set("c1", record("c1", { model: "a/two" }));
    const { assistant, context, run } = setup({ defaultModel: "a/one" }, fake);
    await (
      await assistant.respond(
        post({ id: "c1", message: userMessage() }),
        context,
      )
    ).text();
    expect(run.mock.calls[0]?.[0].model).toBe("a/two");
    const empty = fakeChats({ models: [] });
    empty.raw.set("c9", record("c9", { model: "z/any" }));
    const free = setup({}, empty);
    await (
      await free.assistant.respond(
        post({ id: "c9", message: userMessage() }),
        free.context,
      )
    ).text();
    expect(free.run.mock.calls[0]?.[0].model).toBe("z/any");
  });

  it("falls back to the first allowed model", async () => {
    const fake = fakeChats({ models: ["a/only"] });
    const { assistant, context, run } = setup({ defaultModel: "b/gone" }, fake);
    await (
      await assistant.respond(
        post({ id: "c1", message: userMessage() }),
        context,
      )
    ).text();
    expect(run.mock.calls[0]?.[0].model).toBe("a/only");
  });

  it("blocks and records moderated messages", async () => {
    const moderate = vi
      .fn<NonNullable<AssistantOptions["moderate"]>>()
      .mockResolvedValueOnce({ action: "block", category: "pii", score: 0.9 })
      .mockResolvedValueOnce({ action: "flag", category: "tone" })
      .mockResolvedValueOnce({ action: "allow", category: "none" });
    const { assistant, context, fake } = setup({ moderate });
    const blocked = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(blocked.status).toBe(403);
    expect(await blocked.json()).toMatchObject({
      code: "AI_MODERATION_BLOCKED",
    });
    const flagged = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(flagged.status).toBe(200);
    await flagged.text();
    const allowed = await assistant.respond(
      post({ id: "c1", message: userMessage("u2") }),
      context,
    );
    await allowed.text();
    expect(fake.moderated).toEqual([
      expect.objectContaining({ action: "block", score: 0.9, stage: "input" }),
      expect.objectContaining({ action: "flag", category: "tone" }),
    ]);
  });

  it("answers 429 when the quota is used up", async () => {
    const { assistant, context, run } = setup({
      quota: async () =>
        dbError("quota_exceeded", "used up", { meter: "ai", retryAfter: 9 }),
    });
    const response = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("9");
    expect(run).not.toHaveBeenCalled();
    const open = setup({ quota: async () => undefined });
    expect(
      (
        await open.assistant.respond(
          post({ id: "c1", message: userMessage() }),
          open.context,
        )
      ).status,
    ).toBe(200);
  });

  it("answers 409 while another answer runs", async () => {
    const { assistant, context } = setup({}, fakeChats({ claimed: false }));
    const response = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(response.status).toBe(409);
  });

  it("releases the run when the model can't start", async () => {
    const { assistant, context, fake } = setup({
      run: () => {
        throw new Error("no key");
      },
    });
    const response = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(response.status).toBe(500);
    expect(fake.released).toEqual([
      {
        chatId: "c1",
        streamId: "id1",
        opts: { status: "error", error: "Error: no key" },
      },
    ]);
  });

  it("passes block errors through", async () => {
    const { assistant, context } = setup(
      {},
      fakeChats({ getError: dbError("forbidden", "no") }),
    );
    expect(
      (
        await assistant.respond(
          post({ id: "c1", message: userMessage() }),
          context,
        )
      ).status,
    ).toBe(403);
    expect((await assistant.resume("c1", context)).status).toBe(403);
  });

  it("stops the running answer", async () => {
    const { assistant, context, fake } = setup();
    expect((await assistant.stop("c1", context)).status).toBe(204);
    expect((await assistant.stop("missing", context)).status).toBe(403);
    expect(fake.stops).toEqual(["c1", "missing"]);
  });
});
