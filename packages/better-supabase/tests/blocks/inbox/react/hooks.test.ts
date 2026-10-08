import type { QueryClient } from "@tanstack/query-core";
import type * as ReactModule from "react";

import { afterEach, describe, expect, it, vi } from "vitest";

import type { AuthSnapshot } from "../../../../src/client/index.ts";

import {
  useConversation,
  useInbox,
  useInboxWidget,
} from "../../../../src/blocks/inbox/react/index.ts";
import { defineSupabase } from "../../../../src/core/define.ts";
import {
  BetterSupabaseProvider,
  type ClientLike,
} from "../../../../src/react/hooks.ts";
import { defineSchema } from "../../../../src/schema/define.ts";
import { schema } from "../../../fixtures/generated-camel.ts";

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
      if (!changed(cell.deps, deps)) return;
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
        if (result instanceof Promise) result.catch(() => undefined);
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

const betterSupabase = defineSupabase(defineSchema(schema.meta));

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
        send: vi.fn(async (_message: unknown) => "ok" as const),
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

afterEach(() => {
  runtime.state.render = () => undefined;
  vi.unstubAllGlobals();
});

const sendOf = (client: ReturnType<typeof fakeRealtime>["client"], index = 0) =>
  client.channel.mock.results[index]?.value.send as ReturnType<typeof vi.fn>;

describe("useInbox", () => {
  it("loads and reloads on the organization's pings", async () => {
    const { browser, client, emit } = fakeBrowser(signedIn(USER));
    let rows = ["a"];
    const onMessage = vi.fn();
    const view = renderHook(
      () =>
        useInbox({
          organizationId: "org-1",
          load: async () => rows,
          onMessage,
        }),
      undefined,
      { client: browser },
    );
    await flush();
    await flush();
    expect(view.result.items).toEqual(["a"]);
    expect(view.result.status).toBe("subscribed");
    expect(client.channel.mock.calls[0]?.[0]).toBe("inbox:org:org-1");
    rows = ["a", "b"];
    emit("inbox:org:org-1", "message", { conversation_id: "c1" });
    await flush();
    expect(view.result.items).toEqual(["a", "b"]);
    expect(onMessage).toHaveBeenCalledWith("message", {
      conversation_id: "c1",
    });
    view.unmount();
    expect(client.removeChannel).toHaveBeenCalledTimes(1);
  });

  it("waits for an organization and a user, and keeps load errors", async () => {
    const out = fakeBrowser(SIGNED_OUT);
    const load = vi.fn(async () => []);
    renderHook(() => useInbox({ organizationId: "org-1", load }), undefined, {
      client: out.browser,
    }).unmount();
    const none = fakeBrowser(signedIn(USER));
    renderHook(() => useInbox({ organizationId: null, load }), undefined, {
      client: none.browser,
    }).unmount();
    await flush();
    expect(load).not.toHaveBeenCalled();

    const { browser, client } = fakeBrowser(signedIn(USER));
    const view = renderHook(
      () =>
        useInbox({
          organizationId: "org-1",
          topic: "support",
          load: () => Promise.reject(new Error("offline")),
        }),
      undefined,
      { client: browser },
    );
    await flush();
    expect(client.channel.mock.calls[0]?.[0]).toBe("support:org:org-1");
    expect(view.result.error).toEqual(new Error("offline"));
    view.unmount();
  });
});

describe("useConversation", () => {
  it("tracks messages, typing and the channel status", async () => {
    const { browser, client, emit, channels } = fakeBrowser(signedIn(USER));
    let rows = ["m1"];
    const view = renderHook(
      () =>
        useConversation({
          conversationId: "c1",
          load: async () => rows,
          typingMs: 20,
        }),
      undefined,
      { client: browser },
    );
    await flush();
    await flush();
    expect(view.result.items).toEqual(["m1"]);
    expect(view.result.status).toBe("subscribed");
    expect(client.channel).toHaveBeenCalledWith("inbox:c1", {
      config: { private: true, broadcast: { self: false } },
    });

    emit("inbox:c1", "typing", { user_id: OTHER });
    emit("inbox:c1", "typing", { user_id: USER });
    emit("inbox:c1", "typing", "junk");
    emit("inbox:c1", "typing", {});
    expect(view.result.typing).toEqual([OTHER]);
    emit("inbox:c1", "typing", { user_id: OTHER, typing: false });
    expect(view.result.typing).toEqual([]);
    emit("inbox:c1", "typing", { user_id: OTHER, typing: true });
    emit("inbox:c1", "typing", { user_id: OTHER, typing: true });
    await wait(40);
    expect(view.result.typing).toEqual([]);

    view.result.setTyping(true);
    expect(sendOf(client)).toHaveBeenCalledWith({
      type: "broadcast",
      event: "typing",
      payload: { user_id: USER, typing: true },
    });

    rows = ["m1", "m2"];
    emit("inbox:c1", "message", {});
    await flush();
    expect(view.result.items).toEqual(["m1", "m2"]);

    const status = channels.get("inbox:c1")?.status;
    status?.("CHANNEL_ERROR");
    expect(view.result.status).toBe("error");
    status?.("TIMED_OUT");
    status?.("CLOSED");
    expect(view.result.status).toBe("closed");
    rows = ["m1", "m2", "m3"];
    status?.("SUBSCRIBED");
    await flush();
    expect(view.result.items).toHaveLength(3);
    expect(() => status?.("NOPE")).toThrow(/Unknown realtime status/);

    emit("inbox:c1", "typing", { user_id: OTHER });
    view.unmount();
    expect(client.removeChannel).toHaveBeenCalledTimes(1);
  });

  it("does not join while waiting, and cannot type signed out", async () => {
    const { browser, client } = fakeBrowser(SIGNED_OUT);
    const view = renderHook(
      () => useConversation({ conversationId: "c1", load: async () => [] }),
      undefined,
      { client: browser },
    );
    view.result.setTyping(true);
    const waiting = fakeBrowser(signedIn(USER));
    renderHook(
      () => useConversation({ conversationId: null, load: async () => [] }),
      undefined,
      {
        client: waiting.browser,
      },
    ).unmount();
    await flush();
    expect(client.channel).not.toHaveBeenCalled();
    expect(waiting.client.channel).not.toHaveBeenCalled();
    view.unmount();
  });

  it("leaves before the auth refresh finishes", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    const view = renderHook(
      () => useConversation({ conversationId: "c1", load: async () => [] }),
      undefined,
      { client: browser },
    );
    view.unmount();
    await flush();
    expect(client.removeChannel).toHaveBeenCalledTimes(1);
  });
});

describe("useInboxWidget", () => {
  function memoryStorage() {
    const items = new Map<string, string>();
    return {
      getItem: (key: string) => items.get(key) ?? null,
      setItem: (key: string, value: string) => void items.set(key, value),
      removeItem: (key: string) => void items.delete(key),
      items,
    };
  }

  it("opens on the first message and sends into it after", async () => {
    const storage = memoryStorage();
    vi.stubGlobal("localStorage", storage);
    const { browser, client } = fakeBrowser(signedIn(USER));
    const open = vi.fn(async () => "c9");
    const send = vi.fn(async () => undefined);
    const load = vi.fn(async (id: string) => [`${id}:m`]);
    const view = renderHook(
      () => useInboxWidget({ open, send, load }),
      undefined,
      { client: browser },
    );
    await flush();
    expect(view.result.conversationId).toBeNull();
    expect(view.result.items).toBeUndefined();

    await view.result.submit("hello");
    await flush();
    await flush();
    expect(open).toHaveBeenCalledWith("hello");
    expect(storage.items.get("better-supabase:inbox-widget")).toBe("c9");
    expect(view.result.conversationId).toBe("c9");
    expect(view.result.items).toEqual(["c9:m"]);
    expect(client.channel.mock.calls.at(-1)?.[0]).toBe("inbox:c9");

    await view.result.submit("again");
    expect(send).toHaveBeenCalledWith("c9", "again");
    view.result.reset();
    expect(storage.items.size).toBe(0);
    expect(view.result.conversationId).toBeNull();
    view.unmount();
  });

  it("resumes a stored conversation and works without storage", async () => {
    const storage = memoryStorage();
    storage.setItem("widget", "c3");
    vi.stubGlobal("localStorage", storage);
    const { browser } = fakeBrowser(signedIn(USER));
    const load = vi.fn(async () => ["x"]);
    const options = {
      open: async () => "c4",
      send: async () => undefined,
      load,
    };
    const resumed = renderHook(
      () =>
        useInboxWidget({ ...options, storageKey: "widget", topic: "support" }),
      undefined,
      { client: browser },
    );
    await flush();
    expect(resumed.result.conversationId).toBe("c3");
    expect(load).toHaveBeenCalledWith("c3");
    resumed.unmount();

    vi.stubGlobal("localStorage", undefined);
    const bare = fakeBrowser(signedIn(USER));
    const view = renderHook(
      () => useInboxWidget({ ...options, storageKey: null }),
      undefined,
      {
        client: bare.browser,
      },
    );
    await view.result.submit("hi");
    expect(view.result.conversationId).toBe("c4");
    view.result.reset();
    view.unmount();

    Object.defineProperty(globalThis, "localStorage", {
      configurable: true,
      get: () => {
        throw new DOMException("denied", "SecurityError");
      },
    });
    try {
      const denied = fakeBrowser(signedIn(USER));
      const blocked = renderHook(() => useInboxWidget(options), undefined, {
        client: denied.browser,
      });
      expect(blocked.result.conversationId).toBeNull();
      blocked.unmount();
    } finally {
      Reflect.deleteProperty(globalThis, "localStorage");
    }
  });
});
