import { streamText, type UIMessage } from "ai";
import { convertArrayToReadableStream, MockLanguageModelV4 } from "ai/test";
import { Temporal } from "temporal-polyfill";
import { type Mock, vi } from "vitest";

import type {
  AiChat,
  AiChatRecord,
  AiMessage,
  AiStoredMessage,
} from "../../../src/blocks/ai-chat/index.ts";
import type { DbError } from "../../../src/core/errors.ts";
import type { StreamStore } from "../../../src/streams/index.ts";

import {
  type AssistantContext,
  type AssistantOptions,
  type Assistant,
  createAssistant,
} from "../../../src/ai-sdk/chat/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";
import { redisStreamStore } from "../../../src/streams/redis/index.ts";
import { fakeRedis } from "../../streams/fakes.ts";

const NOW = Temporal.Instant.from("2030-01-01T00:00:00Z");
const result = <T>(value: T) => AsyncResult.from(async () => ok(value));
const failure = (error: DbError) => AsyncResult.from(async () => err(error));

export function record(
  id: string,
  over: Partial<AiChatRecord> = {},
): AiChatRecord {
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

export interface FakeChats {
  readonly chats: AiChat;
  readonly raw: Map<string, AiChatRecord>;
  readonly tree: AiStoredMessage[];
  readonly released: unknown[];
  readonly saved: unknown[];
  readonly moderated: unknown[];
  readonly stops: string[];
}

export function fakeChats(options: FakeOptions = {}): FakeChats {
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

export function mockModel(text = "Hello there"): MockLanguageModelV4 {
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

export const userMessage = (id = "u1", text = "Hi"): UIMessage => ({
  id,
  role: "user",
  parts: [{ type: "text", text }],
});

export const post = (body: unknown): Request =>
  new Request("https://app.test/api/chat", {
    method: "POST",
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

export interface AssistantSetup {
  readonly assistant: Assistant;
  readonly context: AssistantContext;
  readonly fake: FakeChats;
  readonly pending: Promise<unknown>[];
  readonly streams: StreamStore;
  readonly run: Mock<AssistantOptions["run"]>;
}

export function setup(
  over: Partial<AssistantOptions> = {},
  fake: FakeChats = fakeChats(),
): AssistantSetup {
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
