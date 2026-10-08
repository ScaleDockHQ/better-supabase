import { createTestMessage } from "@chat-adapter/tests";
import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/chat-sdk/index.ts";

import { createSupabaseState } from "../../src/chat-sdk/index.ts";
import { testChatState } from "../../src/testing/index.ts";

type Args = Readonly<Record<string, unknown>>;

/** The chat_state_* functions over Maps, with the SQL module's semantics. */
function memoryTransport(): BlockTransport & { readonly calls: string[] } {
  const subscriptions = new Set<string>();
  const locks = new Map<string, { token: string; expiresAt: number }>();
  const cache = new Map<string, { value: unknown; expiresAt: number | null }>();
  const lists = new Map<
    string,
    { value: unknown; expiresAt: number | null }[]
  >();
  const queues = new Map<string, { entry: unknown; expiresAt: number }[]>();
  const calls: string[] = [];
  const now = (): number => Date.now();
  const expiry = (ms: unknown): number | null =>
    typeof ms === "number" && ms > 0 ? now() + ms : null;
  const live = (at: number | null): boolean => at === null || at > now();
  const key = (args: Args, name = "key"): string =>
    `${String(args["prefix"])}|${String(args[name])}`;
  const queue = (args: Args) => {
    const id = key(args, "thread_id");
    const kept = (queues.get(id) ?? []).filter((item) => live(item.expiresAt));
    queues.set(id, kept);
    return kept;
  };
  const lockJson = (
    thread: string,
    held: { token: string; expiresAt: number },
  ) => ({
    thread_id: thread,
    token: held.token,
    expires_at: new Date(held.expiresAt).toISOString(),
  });

  const functions: Record<string, (args: Args) => unknown> = {
    chat_state_subscribe: (args) => {
      subscriptions.add(key(args, "thread_id"));
      return null;
    },
    chat_state_unsubscribe: (args) => {
      subscriptions.delete(key(args, "thread_id"));
      return null;
    },
    chat_state_is_subscribed: (args) =>
      subscriptions.has(key(args, "thread_id")),
    chat_state_acquire_lock: (args) => {
      const id = key(args, "thread_id");
      const held = locks.get(id);
      if (held && held.expiresAt > now()) return null;
      const next = {
        token: String(args["token"]),
        expiresAt: now() + Number(args["ttl_ms"]),
      };
      locks.set(id, next);
      return lockJson(String(args["thread_id"]), next);
    },
    chat_state_extend_lock: (args) => {
      const held = locks.get(key(args, "thread_id"));
      if (!held || held.token !== args["token"] || held.expiresAt <= now())
        return false;
      held.expiresAt = now() + Number(args["ttl_ms"]);
      return true;
    },
    chat_state_release_lock: (args) => {
      const id = key(args, "thread_id");
      if (locks.get(id)?.token !== args["token"]) return false;
      return locks.delete(id);
    },
    chat_state_force_release_lock: (args) =>
      locks.delete(key(args, "thread_id")),
    chat_state_get: (args) => {
      const hit = cache.get(key(args));
      return hit && live(hit.expiresAt) ? { value: hit.value } : null;
    },
    chat_state_set: (args) => {
      cache.set(key(args), {
        value: args["value"],
        expiresAt: expiry(args["ttl_ms"]),
      });
      return null;
    },
    chat_state_set_if_not_exists: (args) => {
      const hit = cache.get(key(args));
      if (hit && live(hit.expiresAt)) return false;
      cache.set(key(args), {
        value: args["value"],
        expiresAt: expiry(args["ttl_ms"]),
      });
      return true;
    },
    chat_state_delete: (args) => {
      cache.delete(key(args));
      return null;
    },
    chat_state_append_to_list: (args) => {
      const id = key(args);
      const list = [
        ...(lists.get(id) ?? []).filter((item) => live(item.expiresAt)),
        { value: args["value"], expiresAt: expiry(args["ttl_ms"]) },
      ];
      const max =
        typeof args["max_length"] === "number" ? args["max_length"] : 0;
      lists.set(id, max > 0 ? list.slice(-max) : list);
      return null;
    },
    chat_state_get_list: (args) =>
      (lists.get(key(args)) ?? [])
        .filter((item) => live(item.expiresAt))
        .map((item) => item.value),
    chat_state_enqueue: (args) => {
      const kept = [
        ...queue(args),
        {
          entry: args["entry"],
          expiresAt: new Date(String(args["expires_at"])).getTime(),
        },
      ];
      const max = typeof args["max_size"] === "number" ? args["max_size"] : 0;
      const trimmed = max > 0 ? kept.slice(-max) : kept;
      queues.set(key(args, "thread_id"), trimmed);
      return trimmed.length;
    },
    chat_state_dequeue: (args) => queue(args).shift()?.entry ?? null,
    chat_state_queue_depth: (args) => queue(args).length,
    purge_chat_state: () => 3,
  };

  return {
    calls,
    call: async (_schema, fn, args) => {
      calls.push(fn);
      const run = functions[fn];
      if (!run) throw new Error(`unexpected ${fn}`);
      return structuredClone(run(JSON.parse(JSON.stringify(args)) as Args));
    },
  };
}

const message = (id: string, text: string) => createTestMessage(id, text);

describe("createSupabaseState", () => {
  it("passes the StateAdapter kit", async () => {
    const state = createSupabaseState({ transport: memoryTransport() });
    const report = await testChatState(state, { message, ttlMs: 60 });
    expect(report.checks.filter((check) => !check.ok)).toEqual([]);
  });

  it("keeps bots apart by prefix and purges", async () => {
    const transport = memoryTransport();
    const a = createSupabaseState({ transport, keyPrefix: "a" });
    const b = createSupabaseState({ transport });
    expect(a.keyPrefix).toBe("a");
    expect(b.keyPrefix).toBe("chat-sdk");
    await a.set("k", 1);
    expect(await b.get("k")).toBeNull();
    await a.connect();
    await a.disconnect();
    expect(await a.purge({ batch: 10 })).toBe(3);
    expect(transport.calls).toContain("purge_chat_state");
  });

  it("reads values stored by older rows without the wrapper", async () => {
    const transport: BlockTransport = {
      call: async (_schema, fn) =>
        fn === "chat_state_get"
          ? { value: "bare" }
          : fn === "chat_state_acquire_lock"
            ? { thread_id: "t", token: "x", expires_at: 5 }
            : fn === "chat_state_dequeue"
              ? { message: { text: "not serialized" } }
              : fn === "chat_state_get_list"
                ? null
                : 1,
    };
    const state = createSupabaseState({ transport });
    expect(await state.get("k")).toBe("bare");
    expect(await state.getList("k")).toEqual([]);
    expect(await state.dequeue("t")).toBeNull();
    expect((await state.acquireLock("t", 1))?.expiresAt).toBeTypeOf("number");
  });
});

describe("testChatState", () => {
  it("throws for a state that loses values", async () => {
    const broken = createSupabaseState({ transport: memoryTransport() });
    await expect(
      testChatState(
        { ...broken, get: async () => null },
        { message, ttlMs: 20 },
      ),
    ).rejects.toThrow(/stores values with a TTL/);
  });
});
