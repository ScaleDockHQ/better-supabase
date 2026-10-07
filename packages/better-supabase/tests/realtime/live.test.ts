import { describe, expect, it, vi } from "vitest";

import type { RealtimeClient } from "../../src/realtime/index.ts";
import type { SchemaMeta } from "../../src/schema/types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { liveCount, liveQuery, liveTopic } from "../../src/realtime/live.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { schema } from "../fixtures/generated-camel.ts";

const meta: SchemaMeta = {
  ...schema.meta,
  realtime: { customers: { tenant: "organizationId" }, notes: {} },
};
const betterSupabase = defineSupabase(defineSchema(meta));
const typed = defineSupabase(schema);

function fakeClient(
  first: (topic: string) => readonly [string, unknown?] = () => ["SUBSCRIBED"],
) {
  const channels = new Map<string, Set<() => void>>();
  const statusCallbacks = new Map<
    string,
    (status: string, error?: unknown) => void
  >();
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
        subscribe: (callback: (status: string, error?: unknown) => void) => {
          statusCallbacks.set(topic, callback);
          const [status, error] = first(topic);
          queueMicrotask(() => {
            callback(status, error);
          });
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

const wait = (ms: number) =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

describe("liveTopic", () => {
  it("scopes tenant tables and requires the tenant", () => {
    expect(liveTopic(betterSupabase.meta, "notes")).toBe("bs:t:public.notes");
    expect(liveTopic(betterSupabase.meta, "customers", "o1")).toBe(
      "bs:t:public.customers:o1",
    );
    expect(() => liveTopic(betterSupabase.meta, "customers")).toThrow(
      /pass `tenant`/,
    );
  });

  it("scopes realtime.users tables per user and requires the user", () => {
    const meta = {
      ...betterSupabase.meta,
      realtime: {
        ...betterSupabase.meta.realtime,
        notes: { user: "authorId" },
      },
    };
    expect(liveTopic(meta, "notes", "o1", "u1")).toBe("bs:t:public.notes:u:u1");
    expect(() => liveTopic(meta, "notes", "o1")).toThrow(/pass `user`/);
  });

  it("rejects an unknown table", () => {
    expect(() => liveTopic(betterSupabase.meta, "nope")).toThrow(
      /unknown table "nope"/,
    );
  });
});

describe("liveQuery join states", () => {
  it("resolves ready on CLOSED and reports subscribed", async () => {
    const { client } = fakeClient(() => ["CLOSED"]);
    const statuses: string[] = [];
    const live = liveQuery(betterSupabase, client, ["notes"], {
      onChange: vi.fn(),
      onStatus: (status) => statuses.push(status),
    });
    await live.ready;
    expect(statuses).toEqual(["joining", "subscribed"]);
    await live.unsubscribe();
  });

  it("rejects ready with the channel error, or a named one", async () => {
    const cause = new Error("denied");
    const { client } = fakeClient((topic) =>
      topic.endsWith("notes") ? ["CHANNEL_ERROR", cause] : ["TIMED_OUT"],
    );
    const errors: (Error | undefined)[] = [];
    const notes = liveQuery(betterSupabase, client, ["notes"], {
      onChange: vi.fn(),
      onStatus: (status, error) => {
        if (status === "error") errors.push(error);
      },
    });
    await expect(notes.ready).rejects.toBe(cause);
    const customers = liveQuery(betterSupabase, client, ["customers"], {
      tenant: "o1",
      onChange: vi.fn(),
    });
    await expect(customers.ready).rejects.toThrow(
      "Realtime timed_out on bs:t:public.customers:o1",
    );
    expect(errors).toEqual([cause]);
    await notes.unsubscribe();
    await customers.unsubscribe();
  });

  it("drops a channel that never joined so the next live query starts over", async () => {
    let attempt = 0;
    const { client, raw } = fakeClient(() =>
      attempt++ === 0 ? ["TIMED_OUT"] : ["SUBSCRIBED"],
    );
    const failed = liveQuery(betterSupabase, client, ["notes"], {
      onChange: vi.fn(),
    });
    await expect(failed.ready).rejects.toThrow(
      "Realtime timed_out on bs:t:public.notes",
    );
    expect(raw.removeChannel).toHaveBeenCalledTimes(1);
    const retried = liveQuery(betterSupabase, client, ["notes"], {
      onChange: vi.fn(),
    });
    await retried.ready;
    expect(raw.channel).toHaveBeenCalledTimes(2);
    await failed.unsubscribe();
    await retried.unsubscribe();
    expect(raw.removeChannel).toHaveBeenCalledTimes(2);
  });

  it("rejects an unknown status and wraps non-Error causes", async () => {
    const { client } = fakeClient(() => ["WEIRD"]);
    const errors: (Error | undefined)[] = [];
    const live = liveQuery(betterSupabase, client, ["notes"], {
      onChange: vi.fn(),
      onStatus: (status, error) => {
        if (status === "error") errors.push(error);
      },
    });
    await expect(live.ready).rejects.toThrow("Unknown realtime status WEIRD");
    expect(errors[0]?.message).toBe("Unknown realtime status WEIRD");

    const { client: failing } = fakeClient(() => ["CHANNEL_ERROR", "nope"]);
    const wrapped = liveQuery(betterSupabase, failing, ["notes"], {
      onChange: vi.fn(),
    });
    await expect(wrapped.ready).rejects.toThrow("nope");
    await live.unsubscribe();
    await wrapped.unsubscribe();
  });

  it("wraps a rejected setAuth that is not an Error", async () => {
    const { client, raw } = fakeClient();
    raw.realtime.setAuth.mockRejectedValueOnce("no token");
    const errors: (Error | undefined)[] = [];
    const live = liveQuery(betterSupabase, client, ["notes"], {
      onChange: vi.fn(),
      onStatus: (status, error) => {
        if (status === "error") errors.push(error);
      },
    });
    await expect(live.ready).rejects.toThrow("no token");
    expect(errors[0]).toBeInstanceOf(Error);
    expect(errors[0]?.message).toBe("no token");
    await live.unsubscribe();
  });

  it("reports closed with no broadcasting tables and never subscribes", async () => {
    const { client, raw } = fakeClient();
    const statuses: string[] = [];
    const live = liveQuery(betterSupabase, client, ["organizations"], {
      onChange: vi.fn(),
      onStatus: (status) => statuses.push(status),
    });
    await live.ready;
    expect(live.tables).toEqual([]);
    expect(live.unwatched).toEqual(["organizations"]);
    expect(raw.channel).not.toHaveBeenCalled();
    expect(statuses).toEqual(["closed"]);
  });

  it("drops a pending change on unsubscribe and unsubscribes once", async () => {
    const { client, raw, emit } = fakeClient();
    const onChange = vi.fn();
    const statuses: string[] = [];
    const live = liveQuery(betterSupabase, client, ["notes"], {
      onChange,
      debounceMs: 5,
      onStatus: (status) => statuses.push(status),
    });
    await live.ready;
    emit("bs:t:public.notes");
    await live.unsubscribe();
    await live.unsubscribe();
    await wait(15);
    expect(onChange).not.toHaveBeenCalled();
    expect(raw.removeChannel).toHaveBeenCalledTimes(1);
    expect(statuses.filter((status) => status === "closed")).toHaveLength(1);
  });

  it("disposes with using", async () => {
    const { client, raw } = fakeClient();
    {
      using live = liveQuery(betterSupabase, client, ["notes"], {
        onChange: vi.fn(),
      });
      await live.ready;
    }
    await wait(1);
    expect(raw.removeChannel).toHaveBeenCalledTimes(1);
  });
});

describe("liveQuery", () => {
  it("watches the broadcasting tables a spec reads and debounces changes", async () => {
    const { client, emit } = fakeClient();
    const onChange = vi.fn();
    const statuses: string[] = [];
    const live = liveQuery(
      betterSupabase,
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
    const a = liveQuery(betterSupabase, client, ["notes"], {
      onChange: first,
      debounceMs: 1,
    });
    const b = liveQuery(betterSupabase, client, ["notes"], {
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

  it("keeps the channel when a subscriber re-joins in the same tick", async () => {
    const { client, raw, emit } = fakeClient();
    const first = liveQuery(betterSupabase, client, ["notes"], {
      onChange: vi.fn(),
    });
    await first.ready;
    const leaving = first.unsubscribe();
    const onChange = vi.fn();
    const second = liveQuery(betterSupabase, client, ["notes"], {
      onChange,
      debounceMs: 1,
    });
    await leaving;
    expect(raw.removeChannel).not.toHaveBeenCalled();
    expect(raw.channel).toHaveBeenCalledTimes(1);
    await second.ready;
    emit("bs:t:public.notes");
    await wait(10);
    expect(onChange).toHaveBeenCalledTimes(1);
    await second.unsubscribe();
    expect(raw.removeChannel).toHaveBeenCalledTimes(1);
  });

  it("refetches once after the channel rejoins", async () => {
    const { client, status } = fakeClient();
    const onChange = vi.fn();
    const live = liveQuery(betterSupabase, client, ["notes"], {
      onChange,
      debounceMs: 1,
    });
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
    const live = liveCount(betterSupabase, client, { $run: run }, spec, {
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
    const live = liveCount(betterSupabase, client, { $run: run }, spec, {
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

  it("passes tenant, debounce and status through, and ignores answers after dispose", async () => {
    const { client, raw, emit } = fakeClient();
    let release: (value: number) => void = () => undefined;
    const run = vi.fn(() =>
      AsyncResult.from(async () => ({
        ok: true as const,
        data: await new Promise<number>((resolve) => {
          release = resolve;
        }),
        error: null,
      })),
    );
    const counts: number[] = [];
    const statuses: string[] = [];
    {
      using live = liveCount(
        betterSupabase,
        client,
        { $run: run },
        typed.spec.customers.count(),
        {
          tenant: "o1",
          debounceMs: 1,
          onCount: (count) => counts.push(count),
          onStatus: (status) => statuses.push(status),
        },
      );
      await live.ready;
      expect(raw.channel).toHaveBeenCalledWith("bs:t:public.customers:o1", {
        config: { private: true },
      });
    }
    release(4);
    await wait(5);
    emit("bs:t:public.customers:o1");
    await wait(5);
    expect(run).toHaveBeenCalledTimes(1);
    expect(counts).toEqual([]);
    expect(statuses).toEqual(["joining", "subscribed", "closed"]);
  });

  it("drops errors without onError", async () => {
    const { client } = fakeClient();
    const run = vi.fn(() => AsyncResult.err(dbError("network", "offline")));
    const onCount = vi.fn();
    const live = liveCount(betterSupabase, client, { $run: run }, spec, {
      onCount,
    });
    await live.ready;
    await wait(1);
    expect(run).toHaveBeenCalledTimes(1);
    expect(onCount).not.toHaveBeenCalled();
    await live.unsubscribe();
  });
});
