import type { StandardSchemaV1 } from "@standard-schema/spec";
import type * as ReactModule from "react";

import { QueryClient } from "@tanstack/query-core";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { AuthSnapshot } from "../../src/client/index.ts";
import type { SchemaMeta } from "../../src/schema/types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import {
  BetterSupabaseProvider,
  type ClientLike,
  createHooks,
  useAuth,
  useBroadcast,
  useLiveCount,
  useLiveQuery,
  useSupabase,
} from "../../src/react/hooks.ts";
import { useSession } from "../../src/react/session.ts";
import { defineTopic } from "../../src/realtime/index.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { schema } from "../fixtures/generated-camel.ts";

/**
 * A synchronous hook runtime standing in for React's dispatcher: no DOM
 * renderer is installed, and effects are what these hooks are about.
 * Effects run after each render; state updates re-render.
 */
const runtime = vi.hoisted(() => {
  interface Slot {
    value?: unknown;
    deps?: readonly unknown[] | undefined;
    cleanup?: (() => void) | undefined;
    setter?: (next: unknown) => void;
    subscribe?: unknown;
  }
  const state = {
    slots: [] as Slot[],
    index: 0,
    pending: [] as (() => void)[],
    provided: new Map<object, unknown>(),
    rendering: false,
    flushing: false,
    dirty: false,
    renders: 0,
    render: (() => undefined) as () => void,
  };
  const slot = (): Slot => {
    const index = state.index;
    state.index += 1;
    return (state.slots[index] ??= {});
  };
  const changed = (
    before: readonly unknown[] | undefined,
    after: readonly unknown[] | undefined,
  ): boolean =>
    before === undefined ||
    after === undefined ||
    before.length !== after.length ||
    before.some((value, index) => !Object.is(value, after[index]));
  const schedule = (): void => {
    if (state.rendering || state.flushing) state.dirty = true;
    else state.render();
  };
  return { state, slot, changed, schedule };
});

vi.mock("react", async (importOriginal) => {
  const actual = await importOriginal<typeof ReactModule>();
  const { state, slot, changed, schedule } = runtime;
  return {
    ...actual,
    createElement: (
      type: unknown,
      props: { value?: unknown } | null,
      ...children: unknown[]
    ) => {
      // A context object is its own provider in React 19.
      if (typeof type === "object" && type !== null && "Consumer" in type)
        state.provided.set(type, props?.value);
      return { type, props, children };
    },
    // The only context here is the browser context, whose default is null.
    useContext: (context: object) => state.provided.get(context) ?? null,
    useState: (initial: unknown) => {
      const cell = slot();
      if (!cell.setter) {
        cell.value = typeof initial === "function" ? initial() : initial;
        cell.setter = (next) => {
          const value = typeof next === "function" ? next(cell.value) : next;
          if (Object.is(value, cell.value)) return;
          cell.value = value;
          schedule();
        };
      }
      return [cell.value, cell.setter];
    },
    useRef: (initial: unknown) => {
      const cell = slot();
      if (!("value" in cell)) cell.value = { current: initial };
      return cell.value;
    },
    useMemo: (factory: () => unknown, deps: readonly unknown[]) => {
      const cell = slot();
      if (changed(cell.deps, deps)) {
        cell.value = factory();
        cell.deps = deps;
      }
      return cell.value;
    },
    useEffect: (
      effect: () => (() => void) | undefined,
      deps?: readonly unknown[],
    ) => {
      const cell = slot();
      if (!changed(cell.deps, deps)) return;
      cell.deps = deps;
      state.pending.push(() => {
        cell.cleanup?.();
        const cleanup = effect();
        cell.cleanup = typeof cleanup === "function" ? cleanup : undefined;
      });
    },
    useSyncExternalStore: (
      subscribe: (listener: () => void) => () => void,
      getSnapshot: () => unknown,
    ) => {
      const cell = slot();
      if (cell.subscribe !== subscribe) {
        cell.cleanup?.();
        cell.subscribe = subscribe;
        cell.cleanup = subscribe(() => {
          if (!Object.is(getSnapshot(), cell.value)) schedule();
        });
      }
      cell.value = getSnapshot();
      return cell.value;
    },
  };
});

/** Renders the provider and `hook` together; returns the latest result. */
function renderHook<P, R>(
  hook: (props: P) => R,
  initial: P,
  provider: { client: ClientLike; queryClient?: QueryClient } | null,
) {
  const { state } = runtime;
  state.slots = [];
  state.provided = new Map();
  state.renders = 0;
  let props = initial;
  const out: { result?: R; error?: Error } = {};
  // Effects set `dirty` through state updates, which control flow can't see.
  const dirty = (): boolean => state.dirty;
  state.render = () => {
    do {
      state.dirty = false;
      state.rendering = true;
      state.index = 0;
      state.renders += 1;
      try {
        if (provider) BetterSupabaseProvider(provider);
        out.result = hook(props);
        delete out.error;
      } catch (cause) {
        out.error = cause instanceof Error ? cause : new Error(String(cause));
      } finally {
        state.rendering = false;
      }
      state.flushing = true;
      try {
        for (const effect of state.pending.splice(0)) effect();
      } finally {
        state.flushing = false;
      }
    } while (dirty());
  };
  state.render();
  return {
    get result(): R {
      if (out.error) throw out.error;
      return out.result!;
    },
    get error() {
      return out.error;
    },
    rerender(next: P) {
      props = next;
      state.render();
    },
    unmount() {
      for (const cell of state.slots) cell.cleanup?.();
      state.slots = [];
      state.render = () => undefined;
    },
  };
}

const USER = "00000000-0000-4000-8000-0000000000aa";
const OTHER = "00000000-0000-4000-8000-0000000000bb";
const LOADING: AuthSnapshot = { status: "loading", user: null, claims: null };
const SIGNED_OUT: AuthSnapshot = {
  status: "signed-out",
  user: null,
  claims: null,
};
const signedIn = (
  id: string,
  claims: Record<string, unknown> = {},
): AuthSnapshot => ({
  status: "signed-in",
  user: { id },
  claims: { sub: id, ...claims },
});

const meta: SchemaMeta = {
  ...schema.meta,
  realtime: { customers: { tenant: "organizationId" }, notes: {} },
};
const betterSupabase = defineSupabase(defineSchema(meta));
const typed = defineSupabase(schema);

type Listener = (message: { event: string; payload: unknown }) => void;

function fakeRealtime() {
  const channels = new Map<
    string,
    { broadcast: Set<Listener>; status?: (status: string) => void }
  >();
  const client = {
    channel: vi.fn((topic: string, _options?: unknown) => {
      const entry = { broadcast: new Set<Listener>() } as {
        broadcast: Set<Listener>;
        status?: (status: string) => void;
      };
      channels.set(topic, entry);
      const channel = {
        topic,
        on: (_type: string, _filter: unknown, listener: Listener) => {
          entry.broadcast.add(listener);
          return channel;
        },
        subscribe: (callback: (status: string) => void) => {
          entry.status = callback;
          queueMicrotask(() => {
            callback("SUBSCRIBED");
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
  const emit = (topic: string, event: string, payload: unknown = {}) => {
    for (const listener of channels.get(topic)?.broadcast ?? [])
      listener({ event, payload });
  };
  return { client, channels, emit };
}

function fakeBrowser(initial: AuthSnapshot, run?: ClientLike["db"]) {
  let snapshot = initial;
  const listeners = new Set<() => void>();
  const realtime = fakeRealtime();
  const browser = {
    betterSupabase,
    supabase: realtime.client,
    auth: {
      current: () => snapshot,
      subscribe: (listener: () => void) => {
        listeners.add(listener);
        return () => void listeners.delete(listener);
      },
    },
    db: run ?? { name: "db" },
    queries: { name: "queries" },
  } as unknown as ClientLike;
  const setAuth = (next: AuthSnapshot) => {
    snapshot = next;
    for (const listener of [...listeners]) listener();
  };
  return { browser, setAuth, listeners, ...realtime };
}

const flush = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });
const wait = (ms: number) =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

function cachedClient(...keys: (readonly unknown[])[]) {
  const queryClient = new QueryClient();
  for (const key of keys) queryClient.setQueryData(key, 1);
  const invalidated = (key: readonly unknown[]) =>
    queryClient.getQueryState(key)?.isInvalidated ?? false;
  return { queryClient, invalidated };
}

afterEach(() => {
  runtime.state.render = () => undefined;
});

describe("BetterSupabaseProvider", () => {
  it("drops better-supabase queries when the user changes, not on first sign-in or loading", () => {
    const { browser, setAuth, listeners } = fakeBrowser(LOADING);
    const { queryClient } = cachedClient(["bs", "customers"], ["other"]);
    const remove = vi.spyOn(queryClient, "removeQueries");
    const view = renderHook(() => useAuth(), undefined, {
      client: browser,
      queryClient,
    });
    expect(view.result.status).toBe("loading");

    setAuth(LOADING);
    setAuth(signedIn(USER));
    expect(view.result.status).toBe("signed-in");
    setAuth(signedIn(USER));
    expect(remove).not.toHaveBeenCalled();

    setAuth(SIGNED_OUT);
    expect(remove).toHaveBeenCalledTimes(1);
    expect(remove).toHaveBeenCalledWith({ queryKey: ["bs"] });
    expect(queryClient.getQueryData(["bs", "customers"])).toBeUndefined();
    expect(queryClient.getQueryData(["other"])).toBe(1);

    setAuth(signedIn(OTHER));
    expect(remove).toHaveBeenCalledTimes(2);
    view.unmount();
    expect(listeners.size).toBe(0);
  });

  it("works without a query client", () => {
    const { browser, setAuth } = fakeBrowser(signedIn(USER));
    const view = renderHook(() => useAuth(), undefined, { client: browser });
    setAuth(signedIn(OTHER));
    expect(view.result.user?.id).toBe(OTHER);
  });

  it("explains a missing provider", () => {
    const view = renderHook(() => useSupabase(), undefined, null);
    expect(view.error).toBeInstanceOf(Error);
    expect(view.error!.message).toMatch(/BetterSupabaseProvider/);
  });
});

describe("createHooks", () => {
  it("returns the browser's db, queries and client, re-rendering on auth changes", () => {
    const { browser, setAuth } = fakeBrowser(SIGNED_OUT);
    const hooks = createHooks<typeof browser>();
    expect(hooks.useSession).toBe(useSession);
    expect(hooks.useAuth).toBe(useAuth);
    const view = renderHook(
      () => ({
        db: hooks.useDb(),
        queries: hooks.useQueries(),
        supabase: hooks.useSupabase(),
      }),
      undefined,
      { client: browser },
    );
    expect(view.result).toEqual({
      db: browser.db,
      queries: browser.queries,
      supabase: browser.supabase,
    });
    const before = runtime.state.renders;
    setAuth(signedIn(USER));
    expect(runtime.state.renders).toBeGreaterThan(before);
  });
});

describe("useBroadcast", () => {
  const title: StandardSchemaV1<unknown, { title: string }> = {
    "~standard": {
      version: 1,
      vendor: "test",
      validate: (value) =>
        typeof (value as { title?: unknown }).title === "string"
          ? { value: value as { title: string } }
          : { issues: [{ message: "title is required" }] },
    },
  };
  const room = defineTopic("room:{roomId}", { events: { created: title } });

  it("needs a query client to invalidate", () => {
    const { browser } = fakeBrowser(SIGNED_OUT);
    const view = renderHook(
      () => useBroadcast(room, { roomId: "r1" }, {}, { invalidate: ["notes"] }),
      undefined,
      { client: browser },
    );
    expect(view.error!.message).toMatch(
      /useBroadcast\(\{ invalidate \}\) needs <BetterSupabaseProvider queryClient/,
    );
  });

  it("waits for auth and values, then subscribes and forwards messages", async () => {
    const { browser, setAuth, client, emit } = fakeBrowser(LOADING);
    const created = vi.fn();
    const other = vi.fn();
    const onInvalid = vi.fn();
    const view = renderHook(
      (values: { roomId: string } | null) =>
        useBroadcast(
          room,
          values,
          { created, "*": other },
          { onInvalid, self: true },
        ),
      null as { roomId: string } | null,
      { client: browser },
    );
    expect(view.result).toBe("closed");
    view.rerender({ roomId: "r1" });
    expect(client.channel).not.toHaveBeenCalled();

    setAuth(signedIn(USER));
    expect(client.channel).toHaveBeenCalledWith("room:r1", {
      config: { private: true, broadcast: { self: true } },
    });
    expect(view.result).toBe("joining");
    await flush();
    expect(view.result).toBe("subscribed");

    emit("room:r1", "created", { title: "Hi" });
    emit("room:r1", "created", { nope: true });
    emit("room:r1", "deleted", { id: 1 });
    await flush();
    expect(created).toHaveBeenCalledWith(
      { title: "Hi" },
      expect.objectContaining({ event: "created", topic: "room:r1" }),
    );
    expect(other).toHaveBeenCalledWith(
      { id: 1 },
      expect.objectContaining({ event: "deleted" }),
    );
    expect(onInvalid).toHaveBeenCalledWith(
      expect.objectContaining({ event: "created" }),
      [{ message: "title is required" }],
    );

    view.unmount();
    expect(client.removeChannel).toHaveBeenCalledTimes(1);
  });

  it("uses the latest handlers without resubscribing, and resubscribes for a new user", async () => {
    const { browser, setAuth, client, emit } = fakeBrowser(signedIn(USER));
    const first = vi.fn();
    const second = vi.fn();
    const view = renderHook(
      (handler: () => void) =>
        useBroadcast(room, { roomId: "r1" }, { created: handler }),
      first as () => void,
      { client: browser },
    );
    await flush();
    view.rerender(second);
    emit("room:r1", "created", { title: "Hi" });
    await flush();
    expect(first).not.toHaveBeenCalled();
    expect(second).toHaveBeenCalledTimes(1);
    expect(client.channel).toHaveBeenCalledTimes(1);
    expect(client.channel.mock.calls[0]![1]).toEqual({
      config: { private: true, broadcast: { self: false } },
    });

    setAuth(signedIn(OTHER));
    expect(client.removeChannel).toHaveBeenCalledTimes(1);
    expect(client.channel).toHaveBeenCalledTimes(2);
    view.unmount();
  });

  it("ignores events without a handler", async () => {
    const { browser, emit } = fakeBrowser(signedIn(USER));
    const plain = defineTopic("plain:{id}");
    const view = renderHook(
      () => useBroadcast(plain, { id: "p1" }),
      undefined,
      { client: browser },
    );
    await flush();
    emit("plain:p1", "anything", { a: 1 });
    await flush();
    expect(view.result).toBe("subscribed");
    view.unmount();
  });

  it("invalidates tables or query keys after each message", async () => {
    const { browser, emit } = fakeBrowser(signedIn(USER));
    const cache = cachedClient(
      ["bs", "notes"],
      ["bs", "customers"],
      ["custom", "r1"],
    );
    const byTables = renderHook(
      () => useBroadcast(room, { roomId: "r1" }, {}, { invalidate: ["notes"] }),
      undefined,
      { client: browser, queryClient: cache.queryClient },
    );
    await flush();
    emit("room:r1", "created", { title: "x" });
    await flush();
    expect(cache.invalidated(["bs", "notes"])).toBe(true);
    expect(cache.invalidated(["bs", "customers"])).toBe(false);
    byTables.unmount();

    const keys = vi.fn((message: { topic: string }) => [
      ["custom", message.topic.split(":")[1]],
    ]);
    const byKeys = renderHook(
      () => useBroadcast(room, { roomId: "r1" }, {}, { invalidate: keys }),
      undefined,
      { client: browser, queryClient: cache.queryClient },
    );
    await flush();
    emit("room:r1", "created", { title: "x" });
    await flush();
    expect(keys).toHaveBeenCalledTimes(1);
    expect(cache.invalidated(["custom", "r1"])).toBe(true);
    expect(cache.invalidated(["bs", "customers"])).toBe(false);
    byKeys.unmount();
  });

  it("forwards nothing to onInvalid when it is not given", async () => {
    const { browser, emit } = fakeBrowser(signedIn(USER));
    const created = vi.fn();
    const view = renderHook(
      () => useBroadcast(room, { roomId: "r1" }, { created }),
      undefined,
      { client: browser },
    );
    await flush();
    emit("room:r1", "created", { nope: true });
    await flush();
    expect(created).not.toHaveBeenCalled();
    view.unmount();
  });
});

describe("useLiveQuery", () => {
  const spec = typed.spec.customers.findMany({ include: { notes: true } });

  it("needs a query client for a spec, not for null", () => {
    const { browser } = fakeBrowser(signedIn(USER));
    const paused = renderHook(() => useLiveQuery(null), undefined, {
      client: browser,
    });
    expect(paused.result).toBe("closed");
    const view = renderHook(() => useLiveQuery(spec), undefined, {
      client: browser,
    });
    expect(view.error!.message).toMatch(
      /useLiveQuery needs <BetterSupabaseProvider queryClient/,
    );
  });

  it("watches with the claimed tenant and invalidates changed tables", async () => {
    const { browser, client, emit, setAuth } = fakeBrowser(LOADING);
    const cache = cachedClient(["bs", "customers"], ["bs", "organizations"]);
    const view = renderHook(
      () => useLiveQuery(spec, { debounceMs: 1 }),
      undefined,
      { client: browser, queryClient: cache.queryClient },
    );
    expect(client.channel).not.toHaveBeenCalled();

    setAuth(signedIn(USER, { app_metadata: { tenant_id: "org-1" } }));
    expect(client.channel.mock.calls.map(([topic]) => topic)).toEqual([
      "bs:t:public.customers:org-1",
      "bs:t:public.notes",
    ]);
    expect(view.result).toBe("joining");
    await flush();
    expect(view.result).toBe("subscribed");

    emit("bs:t:public.customers:org-1", "change");
    await wait(10);
    expect(cache.invalidated(["bs", "customers"])).toBe(true);
    expect(cache.invalidated(["bs", "organizations"])).toBe(false);

    view.unmount();
    await flush();
    expect(client.removeChannel).toHaveBeenCalledTimes(2);
  });

  it("prefers an explicit tenant and resubscribes when it changes", async () => {
    const { browser, client } = fakeBrowser(
      signedIn(USER, { tenant_id: "claimed" }),
    );
    const { queryClient } = cachedClient();
    const view = renderHook<string, string>(
      (tenant) => useLiveQuery(spec, { tenant }),
      "org-a",
      { client: browser, queryClient },
    );
    expect(client.channel.mock.calls[0]![0]).toBe(
      "bs:t:public.customers:org-a",
    );
    view.rerender("org-b");
    await flush();
    expect(client.channel.mock.calls.map(([topic]) => topic)).toContain(
      "bs:t:public.customers:org-b",
    );
    view.unmount();
  });

  it("finds no tenant for signed-out users, so tenant tables throw", () => {
    const { browser } = fakeBrowser(SIGNED_OUT);
    const { queryClient } = cachedClient();
    // The effect throws, as React would surface it to an error boundary.
    expect(() =>
      renderHook(() => useLiveQuery(spec), undefined, {
        client: browser,
        queryClient,
      }),
    ).toThrow(/pass `tenant`/);
  });
});

describe("useLiveCount", () => {
  const spec = typed.spec.notes.count();

  it("counts right away without a seed and keeps the last count on errors", async () => {
    const answers = [
      AsyncResult.ok(4),
      AsyncResult.err(dbError("network", "offline")),
    ];
    const run = vi.fn(() => answers.shift() ?? AsyncResult.ok(0));
    const { browser, emit } = fakeBrowser(signedIn(USER), { $run: run });
    const view = renderHook(
      () => useLiveCount(spec, { debounceMs: 1 }),
      undefined,
      { client: browser },
    );
    expect(view.result.count).toBeUndefined();
    await flush();
    expect(view.result).toEqual({
      count: 4,
      status: "subscribed",
      error: undefined,
    });

    emit("bs:t:public.notes", "change");
    await wait(10);
    expect(view.result.count).toBe(4);
    expect(view.result.error?.kind).toBe("network");
    view.unmount();
  });

  it("shows a seed without fetching until a change", async () => {
    const run = vi.fn(() => AsyncResult.ok(9));
    const { browser, emit } = fakeBrowser(signedIn(USER), { $run: run });
    const view = renderHook(
      () => useLiveCount({ spec, count: 3 }, { debounceMs: 1 }),
      undefined,
      { client: browser },
    );
    await flush();
    expect(view.result.count).toBe(3);
    expect(run).not.toHaveBeenCalled();
    emit("bs:t:public.notes", "change");
    await wait(10);
    expect(view.result.count).toBe(9);
    view.unmount();
  });

  it("uses options.initial, and a null seed count fetches", async () => {
    const run = vi.fn(() => AsyncResult.ok(5));
    const { browser } = fakeBrowser(signedIn(USER), { $run: run });
    const initial = renderHook(
      () => useLiveCount(spec, { initial: 2 }),
      undefined,
      { client: browser },
    );
    await flush();
    expect(initial.result.count).toBe(2);
    expect(run).not.toHaveBeenCalled();
    initial.unmount();

    const unseeded = renderHook(
      () => useLiveCount({ spec, count: null }),
      undefined,
      { client: browser },
    );
    await flush();
    expect(unseeded.result.count).toBe(5);
    unseeded.unmount();
  });

  it("drops the previous spec's count and error when the spec changes", async () => {
    const run = vi
      .fn()
      .mockReturnValueOnce(AsyncResult.ok(1))
      .mockReturnValueOnce(AsyncResult.err(dbError("network", "offline")));
    const { browser } = fakeBrowser(signedIn(USER, { tenant_id: "org-1" }), {
      $run: run,
    });
    const view = renderHook(
      (next: typeof spec | ReturnType<typeof typed.spec.customers.count>) =>
        useLiveCount(next),
      spec as typeof spec | ReturnType<typeof typed.spec.customers.count>,
      { client: browser },
    );
    await flush();
    expect(view.result.count).toBe(1);
    view.rerender(typed.spec.customers.count());
    expect(view.result.count).toBeUndefined();
    await flush();
    expect(view.result).toMatchObject({
      count: undefined,
      error: { kind: "network" },
    });
    view.unmount();
  });

  it("pauses on null and while auth loads", async () => {
    const run = vi.fn(() => AsyncResult.ok(1));
    const { browser, setAuth } = fakeBrowser(LOADING, { $run: run });
    const paused = renderHook(() => useLiveCount(null), undefined, {
      client: browser,
    });
    expect(paused.result).toEqual({
      count: undefined,
      status: "closed",
      error: undefined,
    });
    paused.unmount();
    const view = renderHook(
      () => useLiveCount(spec, { tenant: "t" }),
      undefined,
      { client: browser },
    );
    expect(run).not.toHaveBeenCalled();
    setAuth(signedIn(USER));
    await flush();
    expect(view.result.count).toBe(1);
    view.unmount();
  });
});
