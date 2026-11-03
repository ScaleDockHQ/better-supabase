import type { Adapter, StateAdapter } from "chat";

import { createPostgresState } from "@chat-adapter/state-pg";
import { createMockAdapter, createTestMessage } from "@chat-adapter/tests";
import { Chat } from "chat";
import { Pool } from "pg";
import { afterAll, describe, expect, it, vi } from "vitest";

import type { ChatInboundEvent } from "../../src/chat-sdk/index.ts";

import { createInbox } from "../../src/blocks/inbox/index.ts";
import { sqlTransport } from "../../src/blocks/queue/index.ts";
import {
  chatWebhookPipeline,
  createSupabaseState,
} from "../../src/chat-sdk/index.ts";
import { fakeTransport } from "../blocks/inbox/fixtures.ts";
import { dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const THREAD = "mock:channel:thread";

/**
 * A Chat over a mock adapter whose webhook turns the request body into one
 * message.
 */
function chatOver(state: StateAdapter, onMessage?: () => Promise<void>) {
  let chat: Chat | undefined;

  const adapter: Adapter = createMockAdapter("mock", {
    initialize: async (instance) => {
      // SAFETY: Chat passes itself, which is the Chat built below.
      chat = instance as unknown as Chat;
    },
    handleWebhook: async (request, options) => {
      const { id } = (await request.json()) as { id: string };

      await chat?.processMessage(
        adapter,
        THREAD,
        createTestMessage(id, "hello", { threadId: THREAD }),
        options,
      );

      return new Response("ok");
    },
  });

  const instance = new Chat({
    userName: "bot",
    adapters: { mock: adapter },
    state,
    logger: "silent",
  });

  if (onMessage) {
    instance.onNewMessage(/./, onMessage);
  }

  return instance;
}

const request = (id: string) =>
  new Request("https://app.test/hooks/mock", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ id }),
  });

describe.skipIf(!live)("chat webhook pipeline replay", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 8 });
  const prefixes: string[] = [];

  afterAll(async () => {
    await pool.query(
      "delete from better_supabase.chat_state_cache where key_prefix = any($1)",
      [prefixes],
    );
    await pool.end();
  });

  const supabaseState = (keyPrefix: string): StateAdapter => {
    prefixes.push(keyPrefix);

    return createSupabaseState({
      transport: sqlTransport({
        async queryRaw<T>(text: string, params: unknown[] = []) {
          const { rows } = await pool.query(text, params);

          // SAFETY: the module names the row shape of its own queries.
          return rows as T[];
        },
      }),
      keyPrefix,
    });
  };

  const pgState = (keyPrefix: string): StateAdapter =>
    createPostgresState({ client: pool, keyPrefix });

  const cases: [string, (prefix: string) => StateAdapter][] = [
    ["createSupabaseState", supabaseState],
    ["@chat-adapter/state-pg", pgState],
  ];

  it.each(cases)(
    "replays a stored event on every attempt over %s",
    async (_name, make) => {
      const base = `it-${crypto.randomUUID().slice(0, 8)}`;
      const stored: ChatInboundEvent[] = [];
      let failures = 1;

      const handled = vi.fn(async () => {
        if (failures > 0) {
          failures -= 1;
          throw new Error("handler crashed");
        }
      });

      const pipeline = chatWebhookPipeline({
        chat: chatOver(make(base), handled),
        receiveChat: chatOver(make(`${base}:receive`)),
        adapter: "mock",
        inbox: createInbox({
          transport: fakeTransport({ set_inbound_event_status: true })
            .transport,
        }),
        inboxes: { mock: "i1" },
        sink: {
          store: async (event: {
            payload: { body: string; headers?: Record<string, string> };
          }) => {
            stored.push({
              id: "e1",
              adapter: "mock",
              headers: event.payload.headers ?? {},
              body: event.payload.body,
            });

            return { ok: true, data: { id: "e1", duplicate: false } };
          },
        },
      });

      expect((await pipeline.receive(request("m1"))).status).toBe(200);
      expect(stored).toHaveLength(1);
      // The receiving half runs no handler.
      expect(handled).not.toHaveBeenCalled();

      const event = stored[0]!;

      await expect(pipeline.process({ ...event, attempt: 1 })).rejects.toThrow(
        /handler crashed/,
      );
      await pipeline.process({ ...event, attempt: 2 });
      expect(handled).toHaveBeenCalledTimes(2);
    },
  );

  it.each(cases)(
    "drops the replay as a duplicate when both halves share one prefix over %s",
    async (_name, make) => {
      const prefix = `it-${crypto.randomUUID().slice(0, 8)}`;
      const handled = vi.fn(async () => undefined);
      const state = make(prefix);
      const chat = chatOver(state, handled);

      const body = JSON.stringify({ id: "m1" });

      const send = () =>
        chat.webhooks.mock(
          new Request("https://app.test/hooks/mock", { method: "POST", body }),
          { waitUntil: (task: Promise<unknown>) => void task.catch(() => {}) },
        );

      await send();
      await send();
      await new Promise<void>((resolve) => {
        setTimeout(resolve, 200);
      });
      expect(handled).toHaveBeenCalledOnce();
    },
  );
});
