import { createMockState } from "@chat-adapter/tests";
import { Pool } from "pg";
import { afterAll, describe, expect, it, vi } from "vitest";

import type { SqlClient } from "../../src/postgres/executor.ts";

import {
  createWebhookInbox,
  sqlTransport,
} from "../../src/blocks/queue/index.ts";
import {
  chatEventOf,
  createSupabaseState,
  inboundHandler,
  webhook,
} from "../../src/chat-sdk/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const WEEKS = 30 * 24 * 60 * 60 * 1000;

describe.skipIf(!live)("chat-sdk state and webhook inbox", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 12 });

  afterAll(() => pool.end());

  // Runs each call on its own pooled connection, so calls overlap for real.
  const pooled: SqlClient = {
    async queryRaw<T>(text: string, params: unknown[] = []) {
      const { rows } = await pool.query(text, params);

      // SAFETY: the module names the row shape of its own queries.
      return rows as T[];
    },
  };

  it("keeps the newest 10 entries when 50 appends overlap", async () => {
    const state = createSupabaseState({
      transport: sqlTransport(pooled),
      keyPrefix: `it-${crypto.randomUUID()}`,
    });

    try {
      await Promise.all(
        Array.from({ length: 50 }, (_, index) =>
          state.appendToList("history", index, { maxLength: 10 }),
        ),
      );

      expect(await state.getList("history")).toHaveLength(10);
    } finally {
      await pool.query(
        "delete from better_supabase.chat_state_lists where key_prefix = $1",
        [state.keyPrefix],
      );
    }
  });

  it("stores thread state under a 30 day TTL", async () => {
    const state = createSupabaseState({
      transport: sqlTransport(pooled),
      keyPrefix: `it-${crypto.randomUUID()}`,
    });

    try {
      await state.set("thread-state:t1", { step: 2 }, WEEKS);
      expect(await state.get("thread-state:t1")).toEqual({ step: 2 });
    } finally {
      await pool.query(
        "delete from better_supabase.chat_state_cache where key_prefix = $1",
        [state.keyPrefix],
      );
    }
  });

  it("replays a stored webhook request through the inbound handler", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "incoming-webhooks"]);
      const source = `chat-${crypto.randomUUID().slice(0, 8)}`;

      const inbox = createWebhookInbox({
        transport: sqlTransport(s.sql),
        source,
        verify: () => Promise.reject(new Error("store only")),
      });

      const handle = webhook({
        sink: inbox,
        adapter: "slack",
        externalId: () => "evt-1",
      });

      const request = () =>
        new Request("https://app.test/hooks/slack", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: '{"type":"event_callback"}',
        });

      expect((await handle(request())).status).toBe(200);
      expect((await handle(request())).status).toBe(200);

      const slack = vi.fn(async () => new Response("ok"));
      const state = createMockState();

      const handler = inboundHandler({
        chat: {
          webhooks: { slack },
          getAdapter: () => undefined,
          getState: () => state,
        },
        inbox: {
          apiVersion: 1,
          recordInbound: () => Promise.reject(new Error("not used")),
          recordOutbound: () => Promise.resolve(),
          recordDeliveryAttempt: () => Promise.resolve(),
          updateDeliveryStatus: () => Promise.resolve(0),
          lastInboundAt: () => Promise.resolve(null),
          outbound: () => Promise.resolve(null),
        },
        inboxes: {},
      });

      await inbox.process({
        handler: async (message) => {
          const event = chatEventOf(message);

          if (event) {
            await handler.process(event);
          }
        },
      });

      expect(slack).toHaveBeenCalledOnce();
    } finally {
      await s.close();
    }
  });
});
