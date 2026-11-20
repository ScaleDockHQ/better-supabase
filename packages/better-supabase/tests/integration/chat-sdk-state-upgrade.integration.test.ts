import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { sqlTransport } from "../../src/blocks/queue/index.ts";
import { createSupabaseState } from "../../src/chat-sdk/index.ts";
import { upgradePlan } from "../../src/sql/upgrade.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const DAY = 24 * 60 * 60 * 1000;

// The largest value of a 32-bit integer, which a version 1 ttl_ms could hold.
const INT32_MAX = 2 ** 31 - 1;

describe.skipIf(!live)("chat-sdk state version 2", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("drops the version 1 integer overloads and keeps the bigint ones", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["chat-sdk-state"]);

      // A version 1 install had these overloads next to nothing else.
      await s.client.query(`
        create function better_supabase.chat_state_acquire_lock(prefix text, thread_id text, token text, ttl_ms integer) returns jsonb language sql as 'select null::jsonb';
        create function better_supabase.chat_state_extend_lock(prefix text, thread_id text, token text, ttl_ms integer) returns jsonb language sql as 'select null::jsonb';
        create function better_supabase.chat_state_set(prefix text, key text, value jsonb, ttl_ms integer default null) returns void language sql as 'select';
        create function better_supabase.chat_state_set_if_not_exists(prefix text, key text, value jsonb, ttl_ms integer default null) returns boolean language sql as 'select false';
        create function better_supabase.chat_state_append_to_list(prefix text, key text, value jsonb, max_length integer default null, ttl_ms integer default null) returns void language sql as 'select';`);

      const signatures = () =>
        s.rows<{ name: string; args: string }>(
          `select p.proname as name, pg_get_function_identity_arguments(p.oid) as args
           from pg_proc p
           where p.pronamespace = 'better_supabase'::regnamespace
             and p.proname in ('chat_state_acquire_lock', 'chat_state_extend_lock', 'chat_state_set', 'chat_state_set_if_not_exists', 'chat_state_append_to_list')
           order by 1, 2`,
        );

      expect(await signatures()).toHaveLength(10);

      const [plan] = upgradePlan([{ module: "chat-sdk-state", version: 1 }]);

      expect(plan?.steps.length).toBeGreaterThan(0);

      for (const step of plan!.steps) {
        await s.client.query(step.sql);
      }

      const remaining = await signatures();

      expect(remaining).toHaveLength(5);
      expect(remaining.every((row) => row.args.includes("bigint"))).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("holds a lock and a cache entry for longer than 2^31 milliseconds", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["chat-sdk-state"]);
      await s.service();

      const state = createSupabaseState({
        transport: sqlTransport(s.sql),
        keyPrefix: `ttl-${crypto.randomUUID()}`,
      });

      const ttl = 40 * DAY;

      expect(ttl).toBeGreaterThan(INT32_MAX);

      const lock = await state.acquireLock("thread-1", ttl);

      expect(lock).not.toBeNull();
      expect(await state.acquireLock("thread-1", ttl)).toBeNull();
      expect(await state.extendLock(lock!, ttl + DAY)).toBe(true);

      const [row] = await s.rows<{ days: number }>(
        `select extract(epoch from (expires_at - now())) / 86400 as days
         from better_supabase.chat_state_locks where key_prefix = $1`,
        [state.keyPrefix],
      );

      expect(Number(row?.days)).toBeGreaterThan(40);

      await state.set("thread-state:long", { step: 1 }, ttl);
      expect(await state.get("thread-state:long")).toEqual({ step: 1 });
      expect(await state.setIfNotExists("once", "a", ttl)).toBe(true);
      await state.appendToList("history", "x", { maxLength: 5, ttlMs: ttl });
      expect(await state.getList("history")).toEqual(["x"]);
    } finally {
      await s.close();
    }
  });
});
