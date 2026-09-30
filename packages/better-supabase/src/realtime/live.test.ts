import { describe, expect, it, vi } from "vitest";

import type { SchemaMeta } from "../schema/types.ts";
import type { RealtimeClient } from "./index.ts";

import { defineSupabase } from "../core/define.ts";
import { dbError } from "../core/errors.ts";
import { AsyncResult } from "../core/result.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { defineSchema } from "../schema/define.ts";
import { liveCount, liveQuery, liveTopic } from "./live.ts";

const meta: SchemaMeta = {
  ...schema.meta,
  realtime: { customers: { tenant: "organizationId" }, notes: {} },
};
const sb = defineSupabase(defineSchema(meta));
const typed = defineSupabase(schema);

function fakeClient() {
  const channels = new Map<string, Set<() => void>>();
  const statusCallbacks = new Map<string, (status: string) => void>();
  const client = {
    channel: vi.fn((topic: string, _options: unknown) => {
      const listeners = new Set<() => void>();
      channels.set(topic, listeners);
      const channel = {
        topic,
        on: (_type: string, _filter: unknown, listener: () => void) => {
          listeners.add(listener);
          return channel;
        },
        subscribe: (callback: (status: string) => void) => {
          statusCallbacks.set(topic, callback);
          queueMicrotask(() => callback("SUBSCRIBED"));
          return channel;
        },
      };
      return channel;
    }),
    removeChannel: vi.fn(async (channel: { topic: string }) => {
      channels.delete(channel.topic);
      return "ok" as const;
    }),
    realtime: { setAuth: vi.fn(async () => undefined) },
  };
  const emit = (topic: string) => {
    for (const listener of channels.get(topic) ?? []) listener();
  };
  const status = (topic: string, value: string) =>
    statusCallbacks.get(topic)?.(value);
  return {
    client: client as unknown as RealtimeClient,
    raw: client,
    emit,
    status,
  };
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

describe("liveTopic", () => {
  it("scopes tenant tables and requires the tenant", () => {
    expect(liveTopic(sb.meta, "notes")).toBe("bs:t:public.notes");
    expect(liveTopic(sb.meta, "customers", "o1")).toBe(
      "bs:t:public.customers:o1",
    );
    expect(() => liveTopic(sb.meta, "customers")).toThrow(/pass `tenant`/);
  });
});

describe("liveQuery", () => {
  it("watches the broadcasting tables a spec reads and debounces changes", async () => {
    const { client, emit } = fakeClient();
    const onChange = vi.fn();
    const statuses: string[] = [];
    const live = liveQuery(
      sb,
      client,
      typed.spec.customers.findMany({
        include: { notes: true, organization: true },
      }),
      {
        tenant: "o1",
        debounceMs: 5,
        onChange,
        onStatus: (status) => statuses.push(status),
      },
    );
    expect(live.tables).toEqual(["customers", "notes"]);
    expect(live.unwatched).toEqual(["organizations"]);
    await live.ready;

    emit("bs:t:public.customers:o1");
    emit("bs:t:public.notes");
    emit("bs:t:public.notes");
    await wait(20);
    expect(onChange).toHaveBeenCalledTimes(1);
    expect(onChange).toHaveBeenCalledWith(["customers", "notes"]);

    await live.unsubscribe();
    emit("bs:t:public.notes");
    await wait(20);
    expect(onChange).toHaveBeenCalledTimes(1);
    expect(statuses).toEqual(["joining", "subscribed", "closed"]);
  });

  it("shares one channel per topic and removes it after the last subscriber", async () => {
    const { client, raw, emit } = fakeClient();
    const first = vi.fn();
    const second = vi.fn();
    const a = liveQuery(sb, client, ["notes"], {
      onChange: first,
      debounceMs: 1,
    });
    const b = liveQuery(sb, client, ["notes"], {
      onChange: second,
      debounceMs: 1,
    });
    expect(raw.channel).toHaveBeenCalledTimes(1);
    await Promise.all([a.ready, b.ready]);

    emit("bs:t:public.notes");
    await wait(10);
    expect(first).toHaveBeenCalledTimes(1);
    expect(second).toHaveBeenCalledTimes(1);

    await a.unsubscribe();
    expect(raw.removeChannel).not.toHaveBeenCalled();
    await b.unsubscribe();
    expect(raw.removeChannel).toHaveBeenCalledTimes(1);
  });

  it("refetches once after the channel rejoins", async () => {
    const { client, status } = fakeClient();
    const onChange = vi.fn();
    const live = liveQuery(sb, client, ["notes"], { onChange, debounceMs: 1 });
    await live.ready;
    await wait(5);
    expect(onChange).not.toHaveBeenCalled();

    status("bs:t:public.notes", "CHANNEL_ERROR");
    status("bs:t:public.notes", "SUBSCRIBED");
    await wait(10);
    expect(onChange).toHaveBeenCalledTimes(1);
    expect(onChange).toHaveBeenCalledWith(["notes"]);
    await live.unsubscribe();
  });
});

describe("liveCount", () => {
  const spec = typed.spec.notes.count();

  it("counts now, then after each debounced change, and keeps the count on errors", async () => {
    const { client, emit } = fakeClient();
    const answers = [
      AsyncResult.ok(1),
      AsyncResult.ok(2),
      AsyncResult.err(dbError("network", "offline")),
    ];
    const run = vi.fn(() => answers.shift() ?? AsyncResult.ok(0));
    const counts: number[] = [];
    const errors: string[] = [];
    const live = liveCount(sb, client, { $run: run }, spec, {
      debounceMs: 1,
      onCount: (count) => counts.push(count),
      onError: (error) => errors.push(error.kind),
    });
    await live.ready;
    await wait(5);
    expect(counts).toEqual([1]);

    emit("bs:t:public.notes");
    emit("bs:t:public.notes");
    await wait(10);
    expect(counts).toEqual([1, 2]);
    expect(run).toHaveBeenCalledTimes(2);

    emit("bs:t:public.notes");
    await wait(10);
    expect(errors).toEqual(["network"]);
    await live.unsubscribe();
  });

  it("skips the first count with immediate: false and drops stale answers", async () => {
    const { client, emit } = fakeClient();
    let release: (value: number) => void = () => undefined;
    const slow = new Promise<number>((resolve) => {
      release = resolve;
    });
    const run = vi
      .fn()
      .mockReturnValueOnce(
        AsyncResult.from(async () => ({
          ok: true,
          data: await slow,
          error: null,
        })),
      )
      .mockReturnValueOnce(AsyncResult.ok(7));
    const counts: number[] = [];
    const live = liveCount(sb, client, { $run: run }, spec, {
      immediate: false,
      debounceMs: 1,
      onCount: (count) => counts.push(count),
    });
    await live.ready;
    expect(run).not.toHaveBeenCalled();

    emit("bs:t:public.notes");
    await wait(5);
    emit("bs:t:public.notes");
    await wait(5);
    release(3);
    await wait(5);
    expect(counts).toEqual([7]);
    await live.unsubscribe();
  });
});
