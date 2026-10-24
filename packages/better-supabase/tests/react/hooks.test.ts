import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { SupabaseClient } from "@supabase/supabase-js";
import type * as ReactModule from "react";

import { QueryClient } from "@tanstack/query-core";
import { afterEach, describe, expect, expectTypeOf, it, vi } from "vitest";

import type { AuthSnapshot } from "../../src/client/index.ts";
import type { PowerSyncDatabaseLike } from "../../src/powersync/executor.ts";
import type { SyncStatusLike } from "../../src/powersync/index.ts";
import type { ActionResultOf } from "../../src/react/actions.ts";
import type { ClientLike } from "../../src/react/hooks.ts";
import type {
  LinkingLike,
  UseOAuthOptions,
} from "../../src/react/native/index.ts";
import type { PresenceTopic } from "../../src/react/presence.ts";
import type {
  PresenceMember,
  SubscriptionStatus,
  RealtimeClient,
} from "../../src/realtime/index.ts";
import type { LiveCountSeed } from "../../src/realtime/live.ts";
import type { SchemaMeta } from "../../src/schema/types.ts";

import { fieldErrorsOf } from "../../src/bindings/field-errors.ts";
import { claimedTenant } from "../../src/bindings/keys.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import { createUploadConnector } from "../../src/powersync/connector.ts";
import { powersyncEngine } from "../../src/powersync/index.ts";
import { useAction, useActionForm } from "../../src/react/actions.ts";
import {
  BetterSupabaseProvider,
  createHooks,
  useAuth,
  useBroadcast,
  useBroadcastAuth,
  useLiveCount,
  useLiveQuery,
  useSupabase,
} from "../../src/react/hooks.ts";
import {
  AuthGate,
  useAuthDeepLinks,
  useOAuth,
  useProtectedRoute,
} from "../../src/react/native/index.ts";
import { usePresence } from "../../src/react/presence.ts";
import { useRealtimeRelay } from "../../src/react/relay.ts";
import { useDebouncedSearch } from "../../src/react/search.ts";
import { useSession } from "../../src/react/session.ts";
import { useSignIn, useSignOut } from "../../src/react/sign-in.ts";
import { useImage, useSignedUrl, useUpload } from "../../src/react/storage.ts";
import { useConflicts, useSyncStatus } from "../../src/react/sync.ts";
import { defineTopic } from "../../src/realtime/index.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { schema } from "../fixtures/generated-camel.ts";

/**
 * A synchronous hook runtime standing in for React's dispatcher: no DOM
 * renderer is installed, and effects are what these hooks are about. Effects
 * run after each render; state updates re-render.
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
    if (state.rendering || state.flushing) {
      state.dirty = true;
    } else {
      state.render();
    }
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
      if (typeof type === "object" && type !== null && "Consumer" in type) {
        state.provided.set(type, props?.value);
      }

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

          if (Object.is(value, cell.value)) {
            return;
          }

          cell.value = value;
          schedule();
        };
      }

      return [cell.value, cell.setter];
    },
    useRef: (initial: unknown) => {
      const cell = slot();

      if (!("value" in cell)) {
        cell.value = { current: initial };
      }

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
    useCallback: (fn: unknown, deps: readonly unknown[]) => {
      const cell = slot();

      if (changed(cell.deps, deps)) {
        cell.value = fn;
        cell.deps = deps;
      }

      return cell.value;
    },
    useEffect: (
      effect: () => (() => void) | undefined,
      deps?: readonly unknown[],
    ) => {
      const cell = slot();

      if (!changed(cell.deps, deps)) {
        return;
      }

      cell.deps = deps;
      state.pending.push(() => {
        cell.cleanup?.();
        const cleanup = effect();
        cell.cleanup = typeof cleanup === "function" ? cleanup : undefined;
      });
    },
    // Transitions run at once here; a rejected async one is the boundary's.
    useTransition: () => [
      false,
      (fn: () => unknown) => {
        const result = fn();

        if (result instanceof Promise) {
          result.catch(() => undefined);
        }
      },
    ],
    useSyncExternalStore: (
      subscribe: (listener: () => void) => () => void,
      getSnapshot: () => unknown,
    ) => {
      const cell = slot();

      if (cell.subscribe !== subscribe) {
        cell.cleanup?.();
        cell.subscribe = subscribe;
        cell.cleanup = subscribe(() => {
          if (!Object.is(getSnapshot(), cell.value)) {
            schedule();
          }
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
  provider: {
    client: ClientLike;
    queryClient?: QueryClient;
    realtime?: RealtimeClient;
  } | null,
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
        if (provider) {
          void BetterSupabaseProvider(provider);
        }

        out.result = hook(props);
        delete out.error;
      } catch (cause) {
        out.error = cause instanceof Error ? cause : new Error(String(cause));
      } finally {
        state.rendering = false;
      }

      state.flushing = true;

      try {
        for (const effect of state.pending.splice(0)) {
          effect();
        }
      } finally {
        state.flushing = false;
      }
    } while (dirty());
  };

  state.render();

  return {
    get result(): R {
      if (out.error) {
        throw out.error;
      }

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
      for (const cell of state.slots) {
        cell.cleanup?.();
      }

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
    for (const listener of channels.get(topic)?.broadcast ?? []) {
      listener({ event, payload });
    }
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
    tenant: () => claimedTenant(snapshot, betterSupabase.meta),
    db: run ?? { name: "db" },
    queries: { name: "queries" },
  } as unknown as ClientLike;

  const setAuth = (next: AuthSnapshot) => {
    snapshot = next;

    for (const listener of [...listeners]) {
      listener();
    }
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

  for (const key of keys) {
    queryClient.setQueryData(key, 1);
  }

  const invalidated = (key: readonly unknown[]) =>
    queryClient.getQueryState(key)?.isInvalidated ?? false;

  return { queryClient, invalidated };
}

afterEach(() => {
  runtime.state.render = () => undefined;
});

describe("BetterSupabaseProvider", () => {
  it("resets better-supabase queries when the user changes, not on first sign-in or loading", () => {
    const { browser, setAuth, listeners } = fakeBrowser(LOADING);
    const { queryClient } = cachedClient(["bsb", "customers"], ["other"]);
    const remove = vi.spyOn(queryClient, "resetQueries");

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
    expect(remove).toHaveBeenCalledExactlyOnceWith({ queryKey: ["bsb"] });
    expect(queryClient.getQueryData(["bsb", "customers"])).toBeUndefined();
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

  it("treats a client without the auth module as signed out", () => {
    const view = renderHook(
      () => useBroadcastAuth(undefined, {} as SupabaseClient),
      undefined,
      null,
    );

    expect(view.result).toEqual({ status: "signed-out", userId: null });
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

  it("subscribes with a plain supabase-js client without the provider", async () => {
    const realtime = fakeRealtime();
    const auth = new Set<(event: string, session: unknown) => void>();
    const unsubscribed = vi.fn();

    const supabase = {
      ...realtime.client,
      auth: {
        onAuthStateChange: (
          callback: (event: string, session: unknown) => void,
        ) => {
          auth.add(callback);

          return { data: { subscription: { unsubscribe: unsubscribed } } };
        },
      },
    } as unknown as SupabaseClient;

    const signIn = (id: string | null) => {
      for (const callback of auth) {
        callback("SIGNED_IN", id === null ? null : { user: { id } });
      }
    };

    const created = vi.fn();
    const { queryClient, invalidated } = cachedClient(["bsb", "notes"]);

    const view = renderHook(
      () =>
        useBroadcast(
          room,
          { roomId: "r1" },
          { created },
          { client: supabase, queryClient, invalidate: ["notes"] },
        ),
      undefined,
      null,
    );

    expect(realtime.client.channel).not.toHaveBeenCalled();
    signIn(USER);
    expect(realtime.client.channel).toHaveBeenCalledOnce();
    await flush();
    expect(view.result).toBe("subscribed");
    realtime.emit("room:r1", "created", { title: "Hi" });
    await flush();
    expect(created).toHaveBeenCalledOnce();
    expect(invalidated(["bsb", "notes"])).toBe(true);
    signIn(OTHER);
    expect(realtime.client.channel).toHaveBeenCalledTimes(2);
    view.unmount();
    expect(unsubscribed).toHaveBeenCalledWith();

    const bare = renderHook(
      () => useBroadcast(room, { roomId: "r1" }),
      undefined,
      null,
    );

    expect(bare.error!.message).toMatch(/or \{ client: supabase \}/);
  });

  it("reads the user from the token when tokens-only cookies leave a placeholder user", () => {
    const realtime = fakeRealtime();
    let callback: (event: string, session: unknown) => void = () => undefined;

    const supabase = {
      ...realtime.client,
      auth: {
        onAuthStateChange: (next: typeof callback) => {
          callback = next;

          return { data: { subscription: { unsubscribe: vi.fn() } } };
        },
      },
    } as unknown as SupabaseClient;

    const view = renderHook(
      () => useBroadcast(room, { roomId: "r1" }, {}, { client: supabase }),
      undefined,
      null,
    );

    const payload = btoa(JSON.stringify({ sub: USER })).replace(/[=]+$/, "");

    const placeholder = {
      get id(): string {
        throw new Error("tokens-only placeholder");
      },
    };

    expect(() => {
      callback("SIGNED_IN", {
        access_token: `e30.${payload}.sig`,
        user: placeholder,
      });
    }).not.toThrow();
    expect(realtime.client.channel).toHaveBeenCalledOnce();
    view.unmount();
  });

  it("joins through the provider's realtime client when it has one", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    const relay = fakeRealtime();
    const created = vi.fn();

    const view = renderHook(
      () => useBroadcast(room, { roomId: "r1" }, { created }),
      undefined,
      {
        client: browser,
        // SAFETY: the fake implements the members joinTopic calls.
        realtime: relay.client as unknown as RealtimeClient,
      },
    );

    await flush();
    expect(view.result).toBe("subscribed");
    expect(relay.client.channel).toHaveBeenCalledOnce();
    expect(client.channel).not.toHaveBeenCalled();
    relay.emit("room:r1", "created", { title: "Relayed" });
    await flush();
    expect(created).toHaveBeenCalledOnce();
    view.unmount();
  });

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
    expect(client.removeChannel).toHaveBeenCalledOnce();
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
    expect(second).toHaveBeenCalledOnce();
    expect(client.channel).toHaveBeenCalledOnce();
    expect(client.channel.mock.calls[0]![1]).toEqual({
      config: { private: true, broadcast: { self: false } },
    });

    setAuth(signedIn(OTHER));
    expect(client.removeChannel).toHaveBeenCalledOnce();
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
      ["bsb", "notes"],
      ["bsb", "customers"],
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
    expect(cache.invalidated(["bsb", "notes"])).toBe(true);
    expect(cache.invalidated(["bsb", "customers"])).toBe(false);
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
    expect(keys).toHaveBeenCalledOnce();
    expect(cache.invalidated(["custom", "r1"])).toBe(true);
    expect(cache.invalidated(["bsb", "customers"])).toBe(false);
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
  const spec = typed.spec.customers.list({ include: { notes: true } });

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
    const cache = cachedClient(["bsb", "customers"], ["bsb", "organizations"]);

    const view = renderHook(
      () => useLiveQuery(spec, { debounceMs: 1 }),
      undefined,
      { client: browser, queryClient: cache.queryClient },
    );

    expect(client.channel).not.toHaveBeenCalled();

    setAuth(signedIn(USER, { app_metadata: { tenant_id: "org-1" } }));
    expect(client.channel.mock.calls.map(([topic]) => topic)).toEqual([
      "bsb:t:public.customers:org-1",
      "bsb:t:public.notes",
    ]);
    expect(view.result).toBe("joining");
    await flush();
    expect(view.result).toBe("subscribed");

    emit("bsb:t:public.customers:org-1", "change");
    await wait(10);
    expect(cache.invalidated(["bsb", "customers"])).toBe(true);
    expect(cache.invalidated(["bsb", "organizations"])).toBe(false);

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
      "organization-a",
      { client: browser, queryClient },
    );

    expect(client.channel.mock.calls[0]![0]).toBe(
      "bsb:t:public.customers:organization-a",
    );
    view.rerender("organization-b");
    await flush();
    expect(client.channel.mock.calls.map(([topic]) => topic)).toContain(
      "bsb:t:public.customers:organization-b",
    );
    view.unmount();
  });

  it("keeps the spec it was given and only resubscribes on a different query", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER, { tenant_id: "t" }));
    const { queryClient } = cachedClient();
    const tablesOf = vi.spyOn(browser.betterSupabase, "tablesOf");
    const first = typed.spec.customers.list({ include: { notes: true } });

    const view = renderHook((next: typeof first) => useLiveQuery(next), first, {
      client: browser,
      queryClient,
    });

    expect(tablesOf.mock.calls[0]![0]).toBe(first);
    view.rerender(typed.spec.customers.list({ include: { notes: true } }));
    await flush();
    expect(client.channel).toHaveBeenCalledTimes(2);
    expect(tablesOf).toHaveBeenCalledOnce();
    view.unmount();
  });

  it("invalidates the spec's tables after rejoining the same query", async () => {
    const { browser } = fakeBrowser(signedIn(USER, { tenant_id: "t" }));
    const cache = cachedClient(["bsb", "customers"], ["bsb", "organizations"]);

    const view = renderHook<number, SubscriptionStatus>(
      (debounceMs) => useLiveQuery(spec, { debounceMs }),
      1,
      { client: browser, queryClient: cache.queryClient },
    );

    await flush();
    expect(cache.invalidated(["bsb", "customers"])).toBe(false);
    view.rerender(2);
    await flush();
    expect(cache.invalidated(["bsb", "customers"])).toBe(true);
    expect(cache.invalidated(["bsb", "organizations"])).toBe(false);
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

    emit("bsb:t:public.notes", "change");
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
    emit("bsb:t:public.notes", "change");
    await wait(10);
    expect(view.result.count).toBe(9);
    view.unmount();
  });

  it("counts again after joining when the seed is older than a second", async () => {
    const run = vi.fn(() => AsyncResult.ok(7));
    const { browser } = fakeBrowser(signedIn(USER), { $run: run });

    const fresh = renderHook(
      () => useLiveCount({ spec, count: 3, at: Date.now() }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(run).not.toHaveBeenCalled();
    fresh.unmount();

    const stale = renderHook(
      () => useLiveCount({ spec, count: 3, at: Date.now() - 5000 }),
      undefined,
      { client: browser },
    );

    expect(stale.result.count).toBe(3);
    await flush();
    expect(run).toHaveBeenCalledOnce();
    expect(stale.result.count).toBe(7);
    stale.unmount();
  });

  it("counts again after rejoining, and shows a seed newer than its count", async () => {
    const run = vi.fn(() => AsyncResult.ok(7));
    const { browser } = fakeBrowser(signedIn(USER), { $run: run });

    const view = renderHook(
      (props: { seed: LiveCountSeed; debounceMs: number }) =>
        useLiveCount(props.seed, { debounceMs: props.debounceMs }),
      { seed: { spec, count: 3, at: Date.now() - 5000 }, debounceMs: 1 },
      { client: browser },
    );

    await flush();
    expect(view.result.count).toBe(7);

    const later = { spec, count: 12, at: Date.now() + 1000 };
    view.rerender({ seed: later, debounceMs: 1 });
    expect(view.result.count).toBe(12);

    run.mockClear();
    view.rerender({ seed: later, debounceMs: 2 });
    await flush();
    expect(run).not.toHaveBeenCalled();
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

describe("useAction", () => {
  type Out = ActionResultOf<{ id: string }>;

  const deferred = () => {
    let resolve: (value: Out) => void = () => undefined;
    let reject: (cause: unknown) => void = () => undefined;

    const promise = new Promise<Out>((done, fail) => {
      resolve = done;
      reject = fail;
    });

    return { promise, resolve, reject };
  };

  it("keeps run and reset stable and calls the latest callbacks", async () => {
    const first = vi.fn();
    const latest = vi.fn();
    let onSuccess = first;

    const action = vi.fn(() =>
      Promise.resolve<Out>({ ok: true, data: { id: "a" }, error: null }),
    );

    const view = renderHook(
      () => useAction(action, { onSuccess }),
      undefined,
      null,
    );

    const before = view.result;
    onSuccess = latest;
    view.rerender(undefined);
    // oxlint-disable-next-line typescript/unbound-method -- identity check only; run is never called unbound.
    expect(view.result.run).toBe(before.run);
    // oxlint-disable-next-line typescript/unbound-method -- identity check only; reset is never called unbound.
    expect(view.result.reset).toBe(before.reset);
    await view.result.run({ id: "a" });
    expect(first).not.toHaveBeenCalled();
    expect(latest).toHaveBeenCalledOnce();
    view.unmount();
  });

  it("tracks the inputs in flight and keeps the last data and error", async () => {
    const calls: ReturnType<typeof deferred>[] = [];

    const action = vi.fn((_input: { id: string }) => {
      const call = deferred();
      calls.push(call);

      return call.promise;
    });

    const onSuccess = vi.fn();
    const onError = vi.fn();

    const view = renderHook(
      () => useAction(action, { onSuccess, onError }),
      undefined,
      null,
    );

    expect(view.result.pending).toBe(false);

    const first = view.result.run({ id: "a" });
    const second = view.result.run({ id: "b" });
    expect(view.result.pending).toBe(true);
    expect(view.result.pendingInputs).toEqual([{ id: "a" }, { id: "b" }]);
    expect(view.result.pendingInput).toEqual({ id: "b" });

    calls[0]!.resolve({ ok: true, data: { id: "a" }, error: null });
    await expect(first).resolves.toMatchObject({ ok: true });
    expect(view.result.pendingInputs).toEqual([{ id: "b" }]);
    expect(view.result.data).toEqual({ id: "a" });
    expect(onSuccess).toHaveBeenCalledWith({ id: "a" }, { id: "a" });

    const failure = dbError("forbidden", "no");
    calls[1]!.resolve({ ok: false, data: null, error: failure });
    await second;
    expect(view.result).toMatchObject({
      pending: false,
      data: { id: "a" },
      error: failure,
    });
    expect(onError).toHaveBeenCalledWith(failure, { id: "b" });

    void view.result.run({ id: "c" });
    expect(view.result.error).toBeUndefined();
    calls[2]!.resolve({ ok: true, data: { id: "c" }, error: null });
    await flush();
    view.result.reset();
    expect(view.result).toMatchObject({ data: undefined, error: undefined });
  });

  it("rejects the run when the action throws", async () => {
    const view = renderHook(
      () => useAction(() => Promise.reject(new Error("offline"))),
      undefined,
      null,
    );

    await expect(view.result.run(undefined)).rejects.toThrow("offline");
    expect(view.result.pending).toBe(false);
  });
});

describe("useActionForm", () => {
  class FakeFormData extends FormData {
    constructor(form?: { fields: Record<string, string> }) {
      super();

      for (const [key, value] of Object.entries(form?.fields ?? {})) {
        this.append(key, value);
      }
    }
  }

  const submit = (fields: Record<string, string>) => {
    const form = { fields, reset: vi.fn() };
    const event = { preventDefault: vi.fn(), currentTarget: form };

    return { form, event };
  };

  it("keeps the fields on a failure, maps field errors and resets on success", async () => {
    vi.stubGlobal("FormData", FakeFormData);

    try {
      const action = vi.fn((input: FormData) =>
        Promise.resolve<ActionResultOf<string>>(
          input.get("name") === "x"
            ? {
                ok: false,
                data: null,
                error: dbError("validation", "invalid", {
                  issues: [
                    { message: "Too short", path: ["name"] },
                    { message: "Also short", path: ["name"] },
                    { message: "Form-level" },
                  ],
                }),
              }
            : { ok: true, data: String(input.get("name")), error: null },
        ),
      );

      const onSuccess = vi.fn();
      const onError = vi.fn();

      const view = renderHook(
        () => useActionForm(action, { onSuccess, onError }),
        undefined,
        null,
      );

      const failed = submit({ name: "x" });
      view.result.formProps.onSubmit(failed.event as never);
      await flush();
      expect(failed.event.preventDefault).toHaveBeenCalledWith();
      expect(failed.form.reset).not.toHaveBeenCalled();
      expect(view.result.fieldErrors).toEqual({ name: "Too short" });
      expect(onError).toHaveBeenCalledWith(
        expect.objectContaining({ kind: "validation" }),
        failed.form,
      );

      const saved = submit({ name: "Acme" });
      view.result.formProps.onSubmit(saved.event as never);
      await flush();
      expect(saved.form.reset).toHaveBeenCalledOnce();
      expect(onSuccess).toHaveBeenCalledWith("Acme", saved.form);
      expect(view.result).toMatchObject({ data: "Acme", fieldErrors: {} });
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("can keep the fields after a success", async () => {
    vi.stubGlobal("FormData", FakeFormData);

    try {
      const view = renderHook(
        () =>
          useActionForm(
            () => Promise.resolve({ ok: true, data: 1, error: null } as const),
            { resetOnSuccess: false },
          ),
        undefined,
        null,
      );

      const kept = submit({});
      view.result.formProps.onSubmit(kept.event as never);
      await flush();
      expect(kept.form.reset).not.toHaveBeenCalled();
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("reads field errors only from validation errors", () => {
    expect(fieldErrorsOf(undefined)).toEqual({});
    expect(fieldErrorsOf(dbError("conflict", "x"))).toEqual({});
  });
});

describe("usePresence", () => {
  function fakePresenceTopic() {
    const joins: {
      values: unknown;
      options: {
        onStatus?: (status: SubscriptionStatus) => void;
        onPresence?: (
          members: readonly PresenceMember<{ name: string }>[],
        ) => void;
      };
      tracked: unknown[];
      untracked: number;
      left: boolean;
    }[] = [];

    const topic: PresenceTopic<
      "room:{roomId}",
      { name: string },
      { name: string }
    > = {
      topic: (values) => `room:${values.roomId}`,
      match: (name) =>
        name.startsWith("room:") ? { roomId: name.slice(5) } : null,
      subscribe: (_client, values, _handlers, options = {}) => {
        const join = {
          values,
          options,
          tracked: [] as unknown[],
          untracked: 0,
          left: false,
        };

        joins.push(join);
        options.onStatus?.("subscribed");

        return {
          topic: "x",
          ready: Promise.resolve(),
          track: (state: unknown) => {
            join.tracked.push(state);

            return AsyncResult.from(async () => ok(undefined));
          },
          untrack: () => {
            join.untracked += 1;

            return AsyncResult.from(async () =>
              err(dbError("network", "down")),
            );
          },
          members: () => [],
          unsubscribe: async () => {
            join.left = true;
          },
        } as never;
      },
    };

    return { topic, joins };
  }

  it("joins, tracks the state, re-tracks when it changes and leaves on unmount", async () => {
    const { browser, setAuth } = fakeBrowser(LOADING);
    const { topic, joins } = fakePresenceTopic();

    const initial: { roomId: string | null; name: string | null } = {
      roomId: "r1",
      name: "Ada",
    };

    const view = renderHook(
      (props: typeof initial) =>
        usePresence(topic, props.roomId ? { roomId: props.roomId } : null, {
          state: props.name === null ? null : { name: props.name },
        }),
      initial,
      { client: browser },
    );

    expect(joins).toHaveLength(0);
    expect(await view.result.track({ name: "x" })).toMatchObject({
      kind: "invalid_request",
    });
    setAuth(signedIn(USER));
    expect(joins).toHaveLength(1);
    expect(view.result.status).toBe("subscribed");
    expect(joins[0]!.tracked).toEqual([{ name: "Ada" }]);

    joins[0]!.options.onPresence?.([{ key: "k", state: { name: "Ada" } }]);
    expect(view.result.members).toEqual([{ key: "k", state: { name: "Ada" } }]);

    view.rerender({ roomId: "r1", name: "Ada" });
    expect(joins[0]!.tracked).toHaveLength(1);
    view.rerender({ roomId: "r1", name: "Grace" });
    expect(joins[0]!.tracked).toEqual([{ name: "Ada" }, { name: "Grace" }]);
    view.rerender({ roomId: "r1", name: null });
    expect(joins[0]!.untracked).toBe(1);

    expect(await view.result.track({ name: "Z" })).toBeUndefined();
    expect(await view.result.untrack()).toMatchObject({ kind: "network" });

    view.rerender({ roomId: null, name: null });
    expect(joins[0]!.left).toBe(true);
    expect(view.result.members).toEqual([]);
    expect(view.result.status).toBe("closed");
    view.unmount();
  });

  it("needs a client", () => {
    const { topic } = fakePresenceTopic();

    const view = renderHook(
      () => usePresence(topic, { roomId: "r" }),
      undefined,
      null,
    );

    expect(view.error?.message).toMatch(/usePresence needs/);
  });

  it("accepts a presence topic from defineTopic", () => {
    const room = defineTopic("room:{roomId}", { presence: true });
    expectTypeOf(room).toExtend<
      PresenceTopic<
        "room:{roomId}",
        Readonly<Record<string, unknown>>,
        Readonly<Record<string, unknown>>
      >
    >();
  });
});

describe("useSignIn and useSignOut", () => {
  function fakeAuth() {
    let next: { error: { message: string } | null } = { error: null };

    const auth = {
      signInWithPassword: vi.fn(async () => next),
      signInWithOtp: vi.fn(async () => next),
      verifyOtp: vi.fn(async () => next),
      signInWithOAuth: vi.fn(async () => next),
      signOut: vi.fn(async () => next),
    };

    return {
      client: { auth } as never,
      auth,
      fail: (message: string) => {
        next = { error: { message } };
      },
    };
  }

  it("tracks pending and error and calls onSuccess", async () => {
    const { client, auth, fail } = fakeAuth();
    const onSuccess = vi.fn();

    const view = renderHook(
      () => useSignIn({ client, onSuccess }),
      undefined,
      null,
    );

    expect(view.result.pending).toBe(false);
    const call = view.result.password({ email: "a@b.c", password: "pw" });
    expect(view.result.pending).toBe(true);
    expect(await call).toBeUndefined();
    expect(view.result.pending).toBe(false);
    expect(onSuccess).toHaveBeenCalledOnce();

    await view.result.otp({ email: "a@b.c" });
    await view.result.verifyOtp({ email: "a@b.c", token: "1", type: "email" });
    await view.result.oauth("github");
    await view.result.oauth("github", { redirectTo: "/x" });
    expect(auth.signInWithOAuth).toHaveBeenLastCalledWith({
      provider: "github",
      options: { redirectTo: "/x" },
    });

    fail("bad password");
    expect(await view.result.password({ email: "a", password: "b" })).toEqual({
      message: "bad password",
    });
    expect(view.result.error).toEqual({ message: "bad password" });
    expect(onSuccess).toHaveBeenCalledTimes(5);
  });

  it("resets pending when the call throws", async () => {
    const { client, auth } = fakeAuth();
    auth.signOut.mockRejectedValueOnce(new Error("offline"));
    const view = renderHook(() => useSignOut({ client }), undefined, null);
    await expect(view.result.signOut()).rejects.toThrow("offline");
    expect(view.result.pending).toBe(false);
    await view.result.signOut({ scope: "local" });
    expect(auth.signOut).toHaveBeenLastCalledWith({ scope: "local" });
  });

  it("uses the provider's client and explains a missing one", () => {
    const { browser } = fakeBrowser(SIGNED_OUT);
    const auth = { signOut: vi.fn(async () => ({ error: null })) };
    (browser.supabase as { auth?: unknown }).auth = auth;
    const view = renderHook(() => useSignOut(), undefined, { client: browser });
    void view.result.signOut();
    expect(auth.signOut).toHaveBeenCalledWith(undefined);
    const missing = renderHook(() => useSignIn(), undefined, null);
    expect(missing.error?.message).toMatch(/useSignIn needs/);
  });
});

describe("useDebouncedSearch", () => {
  it("settles after the delay, trims and escapes the pattern", async () => {
    const view = renderHook(
      () => useDebouncedSearch("", { delayMs: 5, minLength: 2 }),
      undefined,
      null,
    );

    expect(view.result.term).toBeUndefined();
    view.result.setValue(" 5");
    expect(view.result.pending).toBe(true);
    await wait(15);
    expect(view.result.term).toBeUndefined();
    view.result.setValue(" 50%_off ");
    expect(view.result.value).toBe(" 50%_off ");
    await wait(15);
    expect(view.result.pending).toBe(false);
    expect(view.result.term).toBe("50%_off");
    expect(view.result.pattern).toBe("%50\\%\\_off%");
    view.unmount();
  });

  it("starts settled with the initial value", () => {
    const view = renderHook(() => useDebouncedSearch("acme"), undefined, null);
    expect(view.result).toMatchObject({ term: "acme", pending: false });
  });
});

describe("useSignedUrl", () => {
  it("signs, re-signs before expiry, keeps the last url on errors and pauses", async () => {
    vi.useFakeTimers();

    try {
      let n = 0;
      let failing = false;

      const bucket = {
        signedUrl: vi.fn((_target: { id: string }) =>
          AsyncResult.from(async () =>
            failing
              ? err(dbError("network", "down"))
              : ok(`url-${String((n += 1))}`),
          ),
        ),
      };

      const initial: { id: string | null } = { id: "a" };

      const view = renderHook(
        (props: typeof initial) =>
          useSignedUrl(bucket, props.id ? { id: props.id } : null, { ttl: 10 }),
        initial,
        null,
      );

      expect(view.result.loading).toBe(true);
      await vi.advanceTimersByTimeAsync(0);
      expect(view.result).toEqual({
        url: "url-1",
        error: undefined,
        loading: false,
      });

      failing = true;
      await vi.advanceTimersByTimeAsync(9000);
      expect(view.result.url).toBe("url-1");
      expect(view.result.error).toMatchObject({ kind: "network" });

      failing = false;
      view.rerender({ id: "b" });
      expect(view.result.url).toBeUndefined();
      await vi.advanceTimersByTimeAsync(0);
      expect(view.result.url).toBe("url-2");

      view.rerender({ id: null });
      expect(view.result).toEqual({
        url: undefined,
        error: undefined,
        loading: false,
      });
      view.unmount();
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("useImage", () => {
  const variants = { md: { width: 96, height: 96, resize: "cover" } } as const;

  it("builds public variant URLs during render, with a srcSet", () => {
    const signedUrl = vi.fn();

    const source = {
      bucket: { id: "avatars", public: true, variants },
      publicUrl: vi.fn(
        (
          target: { id: string },
          options?: { transform?: { width?: number; height?: number } },
        ) =>
          ok(
            `${target.id}@${String(options?.transform?.width)}x${String(options?.transform?.height)}`,
          ),
      ),
      signedUrl,
    };

    const initial: { id: string | null } = { id: "u1" };

    const view = renderHook(
      (props: { id: string | null }) =>
        useImage(source, props.id ? { id: props.id } : null, "md"),
      initial,
      null,
    );

    expect(view.result).toEqual({
      src: "u1@96x96",
      srcSet: "u1@96x96 1x, u1@192x192 2x",
      width: 96,
      height: 96,
      error: undefined,
      loading: false,
    });
    expect(signedUrl).not.toHaveBeenCalled();

    view.rerender({ id: null });
    expect(view.result).toMatchObject({ src: undefined, loading: false });
    view.unmount();
  });

  it("signs each density for private buckets and re-signs before expiry", async () => {
    vi.useFakeTimers();

    try {
      let n = 0;

      const source = {
        bucket: { id: "photos", public: false, variants },
        publicUrl: vi.fn(),
        signedUrl: vi.fn(
          (
            _target: { id: string },
            options?: { transform?: { width?: number } },
          ) =>
            AsyncResult.from(async () =>
              ok(
                `signed-${String((n += 1))}-${String(options?.transform?.width)}`,
              ),
            ),
        ),
      };

      const view = renderHook(
        () => useImage(source, { id: "a" }, "md", { ttl: 10 }),
        undefined,
        null,
      );

      expect(view.result).toMatchObject({ src: undefined, loading: true });
      await vi.advanceTimersByTimeAsync(0);
      expect(view.result).toMatchObject({
        src: "signed-1-96",
        srcSet: "signed-1-96 1x, signed-2-192 2x",
        loading: false,
      });
      expect(source.signedUrl).toHaveBeenCalledWith(
        { id: "a" },
        { ttl: 10, transform: { width: 192, height: 192, resize: "cover" } },
      );
      expect(source.publicUrl).not.toHaveBeenCalled();

      await vi.advanceTimersByTimeAsync(9000);
      expect(view.result.src).toBe("signed-3-96");
      view.unmount();
    } finally {
      vi.useRealTimers();
    }
  });

  it("reports an unknown variant and signing errors", async () => {
    const source = {
      bucket: { id: "photos", public: false, variants },
      publicUrl: vi.fn(),
      signedUrl: vi.fn(() => AsyncResult.err(dbError("forbidden", "no"))),
    };

    const unknown = renderHook(
      // @ts-expect-error "xl" is not a variant
      () => useImage(source, { id: "a" }, "xl"),
      undefined,
      null,
    );

    expect(unknown.result.error).toMatchObject({ kind: "invalid_input" });
    expect(source.signedUrl).not.toHaveBeenCalled();
    unknown.unmount();

    const denied = renderHook(
      () => useImage(source, { id: "a" }, { width: 50 }, { densities: [1] }),
      undefined,
      null,
    );

    await Promise.resolve();
    await new Promise((resolve) => {
      setTimeout(resolve, 0);
    });
    expect(denied.result).toMatchObject({
      src: undefined,
      srcSet: undefined,
      width: 50,
      error: { kind: "forbidden" },
      loading: false,
    });
    denied.unmount();
  });
});

describe("useUpload", () => {
  it("reports progress, success and errors, and aborts the previous upload", async () => {
    const signals: AbortSignal[] = [];
    let release: (() => void) | undefined;

    const bucket = {
      upload: vi.fn(
        (
          target: { id: string },
          _body: unknown,
          options?: { signal?: AbortSignal; onProgress?: (n: number) => void },
        ) =>
          AsyncResult.from(async () => {
            signals.push(options!.signal!);
            options?.onProgress?.(0.5);

            if (target.id === "slow") {
              await new Promise<void>((resolve) => {
                release = resolve;
              });
            }

            if (target.id === "bad") {
              return err(dbError("forbidden", "no"));
            }

            if (target.id === "throw") {
              throw new Error("boom");
            }

            return ok({ path: target.id });
          }),
      ),
    };

    const onSuccess = vi.fn();
    const onError = vi.fn();

    const view = renderHook(
      () => useUpload(bucket, { onSuccess, onError }),
      undefined,
      null,
    );

    expect(view.result.status).toBe("idle");

    const slow = view.result.upload({ id: "slow" }, "x");
    await flush();
    expect(view.result).toMatchObject({ status: "uploading", progress: 0.5 });
    const fast = await view.result.upload({ id: "ok" }, "x", { upsert: true });
    expect(signals[0]!.aborted).toBe(true);
    expect(fast).toMatchObject({ ok: true, data: { path: "ok" } });
    expect(view.result).toMatchObject({
      status: "done",
      progress: 1,
      data: { path: "ok" },
    });
    release?.();
    await slow;
    expect(view.result.data).toEqual({ path: "ok" });
    expect(onSuccess).toHaveBeenCalledOnce();

    await view.result.upload({ id: "bad" }, "x");
    expect(view.result).toMatchObject({
      status: "error",
      error: { kind: "forbidden" },
    });
    expect(onError).toHaveBeenCalledOnce();
    const thrown = await view.result.upload({ id: "throw" }, "x");
    expect(thrown.ok).toBe(false);

    view.result.reset();
    expect(view.result.status).toBe("idle");
    void view.result.upload({ id: "slow" }, "x");
    view.unmount();
    await flush();
    expect(signals.at(-1)!.aborted).toBe(true);
    release?.();
  });
});

describe("react/native", () => {
  function fakeNativeAuth() {
    const auth = {
      exchangeCodeForSession: vi.fn(async (_code: string) => ({ error: null })),
      setSession: vi.fn(async () => ({ error: null })),
      verifyOtp: vi.fn(async () => ({ error: null })),
      signInWithOAuth: vi.fn(async () => ({
        data: { url: "https://auth.example/authorize" },
        error: null,
      })),
      signInWithIdToken: vi.fn(async () => ({ error: null })),
    };

    return { auth, client: { auth } as never };
  }

  it("useOAuth signs in through the browser and with an ID token", async () => {
    const { auth, client } = fakeNativeAuth();
    const onSuccess = vi.fn();
    let redirect = { type: "success", url: "app://cb?code=abc" };

    const browser = { openAuthSessionAsync: vi.fn(async () => redirect) };

    const view = renderHook(
      () => useOAuth({ browser, redirectTo: "app://cb", client, onSuccess }),
      undefined,
      null,
    );

    expect(await view.result.signIn("github")).toBeUndefined();
    expect(auth.exchangeCodeForSession).toHaveBeenCalledWith("abc");
    redirect = { type: "success", url: "app://cb#error_description=Denied" };
    expect(await view.result.signIn("github")).toEqual({ message: "Denied" });
    expect(view.result.error).toEqual({ message: "Denied" });
    await view.result.idToken({ provider: "apple", token: "t", nonce: "n" });
    expect(auth.signInWithIdToken).toHaveBeenCalledWith({
      provider: "apple",
      token: "t",
      nonce: "n",
    });
    expect(onSuccess).toHaveBeenCalledTimes(2);
  });

  it("useAuthDeepLinks handles the initial URL and later links once each", async () => {
    const { auth, client } = fakeNativeAuth();
    const listeners = new Set<(event: { url: string }) => void>();

    const linking: LinkingLike = {
      getInitialURL: async () => "app://cb?code=first",
      addEventListener: (_type, listener) => {
        listeners.add(listener);

        return { remove: () => void listeners.delete(listener) };
      },
    };

    const onResult = vi.fn();

    const view = renderHook(
      () => useAuthDeepLinks(linking, { client, onResult }),
      undefined,
      null,
    );

    await flush();
    expect(view.result).toEqual({ type: "signed-in", via: "code" });

    for (const listener of listeners) {
      listener({ url: "app://home" });
      listener({ url: "app://cb?code=first" });
      listener({ url: "app://cb?token_hash=h&type=email" });
    }

    await flush();
    expect(auth.exchangeCodeForSession).toHaveBeenCalledOnce();
    expect(auth.verifyOtp).toHaveBeenCalledOnce();
    expect(onResult).toHaveBeenCalledTimes(2);
    view.unmount();
    expect(listeners.size).toBe(0);
  });

  it("useProtectedRoute redirects by auth status and route group", () => {
    const { browser, setAuth } = fakeBrowser(LOADING);
    const router = { replace: vi.fn() };
    const initial: { segments: readonly string[] } = { segments: ["(app)"] };

    const view = renderHook(
      (props) => useProtectedRoute({ segments: props.segments, router }),
      initial,
      { client: browser },
    );

    expect(view.result).toBe("loading");
    expect(router.replace).not.toHaveBeenCalled();
    setAuth(SIGNED_OUT);
    expect(router.replace).toHaveBeenLastCalledWith("/sign-in");
    view.rerender({ segments: ["(auth)", "sign-in"] });
    setAuth(signedIn(USER));
    expect(router.replace).toHaveBeenLastCalledWith("/");
    expect(router.replace).toHaveBeenCalledTimes(2);
  });

  it("accepts a real supabase-js client", () => {
    const asClient = (client: SupabaseClient): UseOAuthOptions["client"] =>
      client;

    expectTypeOf(asClient).returns.toEqualTypeOf<UseOAuthOptions["client"]>();
  });

  it("AuthGate picks the branch for the status", () => {
    const { browser, setAuth } = fakeBrowser(LOADING);
    const props = { fallback: "splash", signedOut: "sign-in", children: "app" };

    const view = renderHook(() => AuthGate(props), undefined, {
      client: browser,
    });

    expect(view.result).toBe("splash");
    setAuth(SIGNED_OUT);
    expect(view.result).toBe("sign-in");
    setAuth(signedIn(USER));
    expect(view.result).toBe("app");
    const bare = renderHook(() => AuthGate({}), undefined, { client: browser });
    expect(bare.result).toBeNull();
  });
});

describe("useSyncStatus and useConflicts", () => {
  function syncedDatabase() {
    const listeners = new Set<(status: SyncStatusLike) => void>();

    let status: SyncStatusLike = {
      connected: false,
      dataFlowStatus: { uploading: false, downloading: false },
    };

    const db = {
      execute: vi.fn(),
      getAll: vi.fn(),
      writeTransaction: vi.fn(),
      get currentStatus() {
        return status;
      },
      registerListener: (listener: {
        statusChanged?: (status: SyncStatusLike) => void;
      }) => {
        const notify = (next: SyncStatusLike) => listener.statusChanged?.(next);
        listeners.add(notify);

        return () => void listeners.delete(notify);
      },
    } satisfies PowerSyncDatabaseLike;

    const set = (next: SyncStatusLike) => {
      status = next;

      for (const listener of listeners) {
        listener(next);
      }
    };

    return { db, set };
  }

  it("follows the engine's sync status and re-renders only when a field changes", () => {
    const { browser } = fakeBrowser(signedIn(USER));
    const { db, set } = syncedDatabase();
    const client = { ...browser, engine: powersyncEngine(db) };
    const view = renderHook(() => useSyncStatus(), undefined, { client });

    expect(view.result).toEqual({
      connected: false,
      connecting: false,
      hasSynced: false,
      uploading: false,
      downloading: false,
      error: undefined,
    });
    const before = view.result;
    set({
      connected: false,
      dataFlowStatus: { uploading: false, downloading: false },
    });
    expect(view.result).toBe(before);

    const failure = new Error("upload failed");
    set({
      connected: true,
      hasSynced: true,
      dataFlowStatus: {
        uploading: true,
        downloading: false,
        uploadError: failure,
      },
    });
    expect(view.result).toMatchObject({
      connected: true,
      hasSynced: true,
      uploading: true,
      error: failure,
    });
  });

  it("is undefined when the engine syncs nothing", () => {
    const { browser } = fakeBrowser(signedIn(USER));

    const view = renderHook(() => useSyncStatus(), undefined, {
      client: browser,
    });

    expect(view.result).toBeUndefined();
    const conflicts = renderHook(() => useConflicts(), undefined, null);
    expect(conflicts.result.changes).toEqual([]);
    conflicts.result.dismiss();
  });

  it("follows the connector's refused changes", async () => {
    const connector = createUploadConnector({
      endpoint: "e",
      supabase: {
        auth: { getSession: async () => ({ data: { session: null } }) },
      },
      tables: { notes: async () => err(dbError("conflict", "newer")) },
    });

    const { browser } = fakeBrowser(signedIn(USER));
    const { db } = syncedDatabase();
    const client = { ...browser, engine: powersyncEngine(db, { connector }) };
    const view = renderHook(() => useConflicts(), undefined, { client });
    expect(view.result.changes).toEqual([]);
    await connector.uploadData({
      getCrudBatch: async () => ({
        crud: [{ op: "PUT", table: "notes", id: "1" }],
        complete: async () => undefined,
      }),
    });
    expect(view.result.changes).toHaveLength(1);
    view.result.dismiss();
    expect(view.result.changes).toEqual([]);
  });
});

describe("useRealtimeRelay", () => {
  it("relays only in a support session unless asked to always", () => {
    const outside = renderHook(
      () => useRealtimeRelay("/api/realtime"),
      undefined,
      null,
    );

    expect(outside.result).toBeUndefined();

    const always = renderHook(
      () => useRealtimeRelay("/api/realtime", { when: "always" }),
      undefined,
      null,
    );

    const first = always.result;
    expect(first?.getChannels()).toEqual([]);
    always.rerender(undefined);
    expect(always.result).toBe(first);
  });
});
