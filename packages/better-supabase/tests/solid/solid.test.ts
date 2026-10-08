import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { QueryClient } from "@tanstack/query-core";

import { createRoot, createSignal } from "solid-js";
import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { AuthSession } from "../../src/auth/view.ts";
import type { ActionResultOf, ClientLike } from "../../src/bindings/client.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { defineTopic } from "../../src/realtime/index.ts";
import {
  BetterSupabaseProvider,
  createBindings,
  useAction,
  useAuth,
  useBroadcast,
  useLiveCount,
  useLiveQuery,
  usePresence,
  useSession,
  useSupabase,
  useSupportSession,
} from "../../src/solid/index.ts";
import {
  cachedClient,
  fakeBrowser,
  fakePresenceTopic,
  flush,
  LOADING,
  OTHER,
  SIGNED_OUT,
  signedIn,
  typed,
  USER,
  wait,
} from "../fixtures/fake-browser.ts";

// Node resolves solid-js to its server build, where effects never run.
vi.mock("solid-js", () => {
  const browserBuild = "../../node_modules/solid-js/dist/solid.js";
  return import(browserBuild);
});

interface Mounted<T> {
  readonly result: T;
  readonly dispose: () => void;
}

function mount<T>(
  client: ClientLike | null,
  setup: () => T,
  extra: {
    readonly queryClient?: QueryClient;
    readonly session?: () => AuthSession | undefined;
  } = {},
): Mounted<T> {
  let result: T | undefined;
  let dispose = (): void => undefined;
  createRoot((stop) => {
    dispose = stop;
    if (!client) {
      result = setup();
      return;
    }
    const element = BetterSupabaseProvider({
      client,
      ...extra,
      get children() {
        result = setup();
        return null;
      },
    });
    const rendered: unknown = element;
    if (typeof rendered === "function") rendered();
  });
  // SAFETY: the provider renders its children synchronously.
  return { result: result as T, dispose };
}

const anything: StandardSchemaV1<unknown, unknown> = {
  "~standard": { version: 1, vendor: "test", validate: (value) => ({ value }) },
};

describe("BetterSupabaseProvider", () => {
  it("shares the auth state and resets queries when the user changes", async () => {
    const { browser, setAuth, listeners } = fakeBrowser(signedIn(USER));
    const { queryClient } = cachedClient(["bs", "customers"]);
    const reset = vi.spyOn(queryClient, "resetQueries");
    const view = mount(
      browser,
      () => ({ auth: useAuth(), supabase: useSupabase() }),
      { queryClient },
    );
    await flush();
    expect(view.result.auth().user?.id).toBe(USER);
    expect(view.result.supabase).toBe(browser.supabase);
    setAuth(signedIn(OTHER));
    expect(view.result.auth().user?.id).toBe(OTHER);
    expect(reset).toHaveBeenCalledOnce();
    view.dispose();
    expect(listeners.size).toBe(0);
  });

  it("explains a missing provider and types createBindings", () => {
    expect(() => mount(null, () => useAuth())).toThrow(
      /<BetterSupabaseProvider client=\{bs\}>/,
    );
    const { browser } = fakeBrowser(SIGNED_OUT);
    const bindings = createBindings<typeof browser>();
    const view = mount(browser, () => ({
      db: bindings.useDb(),
      queries: bindings.useQueries(),
    }));
    expect(view.result.db).toBe(browser.db);
    expect(view.result.queries).toBe(browser.queries);
    view.dispose();
  });

  it("reads the session prop", () => {
    const { browser } = fakeBrowser(SIGNED_OUT);
    const session = { user: { id: USER } } as unknown as AuthSession;
    const view = mount(
      browser,
      () => ({ session: useSession(), support: useSupportSession() }),
      { session: () => session },
    );
    expect(view.result.session()).toBe(session);
    expect(view.result.support()).toBeUndefined();
    view.dispose();
    const loading = mount(browser, () => useSupportSession(), {
      session: () => undefined,
    });
    expect(loading.result()).toBeUndefined();
    expect(() => mount(browser, () => useSession())).toThrow(
      /needs <BetterSupabaseProvider session/,
    );
  });
});

describe("useBroadcast", () => {
  const room = defineTopic("room:{roomId}", { events: { created: anything } });

  it("subscribes, forwards messages, pauses on null and resubscribes on a new user", async () => {
    const { browser, client, emit, setAuth } = fakeBrowser(LOADING);
    const cache = cachedClient(["bs", "customers"]);
    const [roomId, setRoomId] = createSignal<string | null>("r1");
    const created = vi.fn();
    const view = mount(
      browser,
      () =>
        useBroadcast(
          room,
          () => {
            const id = roomId();
            return id ? { roomId: id } : null;
          },
          { created },
          { invalidate: ["customers"] },
        ),
      { queryClient: cache.queryClient },
    );
    await flush();
    expect(client.channel).not.toHaveBeenCalled();
    setAuth(signedIn(USER));
    expect(client.channel).toHaveBeenCalledTimes(1);
    await flush();
    expect(view.result()).toBe("subscribed");
    emit("room:r1", "created", {});
    await flush();
    expect(created).toHaveBeenCalledOnce();
    expect(cache.invalidated(["bs", "customers"])).toBe(true);

    setAuth(signedIn(OTHER));
    expect(client.channel).toHaveBeenCalledTimes(2);
    setRoomId(null);
    expect(view.result()).toBe("closed");
    view.dispose();
  });

  it("follows a plain client's auth state without the provider", async () => {
    const { client, emitAuth } = fakeBrowser(LOADING);
    const view = mount(null, () =>
      useBroadcast(room, { roomId: "r" }, undefined, {
        client: client as never,
      }),
    );
    await flush();
    emitAuth({ user: { id: USER }, access_token: "x" });
    expect(client.channel).toHaveBeenCalledOnce();
    view.dispose();
    expect(() =>
      mount(null, () => useBroadcast(room, { roomId: "r" })),
    ).toThrow(/useBroadcast needs/);
  });
});

describe("useLiveQuery", () => {
  const spec = typed.spec.customers.findMany({ include: { notes: true } });

  it("needs a query client for a spec", async () => {
    const { browser } = fakeBrowser(signedIn(USER));
    const paused = mount(browser, () => useLiveQuery(null));
    expect(paused.result()).toBe("closed");
    expect(() => mount(browser, () => useLiveQuery(spec))).toThrow(
      /useLiveQuery needs/,
    );
  });

  it("watches with the claimed tenant, invalidates and rejoins", async () => {
    const { browser, client, emit, setAuth } = fakeBrowser(LOADING);
    const cache = cachedClient(["bs", "customers"], ["bs", "organizations"]);
    const [current, setCurrent] = createSignal<typeof spec | null>(spec);
    const view = mount(
      browser,
      () => useLiveQuery(current, { debounceMs: 1 }),
      {
        queryClient: cache.queryClient,
      },
    );
    await flush();
    setAuth(signedIn(USER, { app_metadata: { tenant_id: "org-1" } }));
    expect(client.channel.mock.calls.map(([topic]) => topic)).toEqual([
      "bs:t:public.customers:org-1",
      "bs:t:public.notes",
    ]);
    await flush();
    expect(view.result()).toBe("subscribed");
    emit("bs:t:public.customers:org-1", "change");
    await wait(10);
    expect(cache.invalidated(["bs", "customers"])).toBe(true);
    expect(cache.invalidated(["bs", "organizations"])).toBe(false);
    setCurrent(null);
    await wait(5);
    expect(client.removeChannel).toHaveBeenCalledTimes(2);
    setCurrent(spec);
    expect(client.channel).toHaveBeenCalledTimes(4);
    view.dispose();
  });
});

describe("useLiveCount", () => {
  const spec = typed.spec.notes.count();

  it("counts, keeps the last count on errors and shows a seed first", async () => {
    const answers = [
      AsyncResult.ok(4),
      AsyncResult.err(dbError("network", "offline")),
    ];
    const run = vi.fn(() => answers.shift() ?? AsyncResult.ok(0));
    const { browser, emit } = fakeBrowser(signedIn(USER), { $run: run });
    const counted = mount(browser, () => useLiveCount(spec, { debounceMs: 1 }));
    expect(counted.result.count).toBeUndefined();
    await flush();
    expect(counted.result.count).toBe(4);
    expect(counted.result.status).toBe("subscribed");
    emit("bs:t:public.notes", "change");
    await wait(10);
    expect(counted.result.count).toBe(4);
    expect(counted.result.error?.kind).toBe("network");
    counted.dispose();

    const seeded = mount(browser, () =>
      useLiveCount({ spec, count: 3 }, { debounceMs: 1 }),
    );
    await flush();
    expect(seeded.result.count).toBe(3);
    seeded.dispose();
  });
});

describe("usePresence", () => {
  it("joins, tracks the state, re-tracks when it changes and leaves", async () => {
    const { browser, setAuth } = fakeBrowser(LOADING);
    const { topic, joins } = fakePresenceTopic();
    const [roomId, setRoomId] = createSignal<string | null>("r1");
    const [name, setName] = createSignal<string | null>("Ada");
    const view = mount(browser, () =>
      usePresence(
        topic,
        () => {
          const id = roomId();
          return id ? { roomId: id } : null;
        },
        {
          state: () => {
            const current = name();
            return current === null ? null : { name: current };
          },
        },
      ),
    );
    await flush();
    expect(joins).toHaveLength(0);
    expect(await view.result.track({ name: "x" })).toMatchObject({
      kind: "invalid_request",
    });
    expect(await view.result.untrack()).toMatchObject({
      kind: "invalid_request",
    });
    setAuth(signedIn(USER));
    expect(joins).toHaveLength(1);
    expect(view.result.status).toBe("subscribed");
    expect(joins[0]!.tracked).toEqual([{ name: "Ada" }]);
    joins[0]!.options.onPresence?.([{ key: "k", state: { name: "Ada" } }]);
    expect(view.result.members).toEqual([{ key: "k", state: { name: "Ada" } }]);

    setName("Grace");
    expect(joins[0]!.tracked).toEqual([{ name: "Ada" }, { name: "Grace" }]);
    setName(null);
    expect(joins[0]!.untracked).toBe(1);
    expect(await view.result.track({ name: "Z" })).toBeUndefined();
    expect(await view.result.untrack()).toMatchObject({ kind: "network" });

    setRoomId(null);
    expect(joins[0]!.left).toBe(true);
    expect(view.result.members).toEqual([]);
    expect(view.result.status).toBe("closed");
    view.dispose();
  });

  it("needs a client", () => {
    const { topic } = fakePresenceTopic();
    expect(() =>
      mount(null, () => usePresence(topic, { roomId: "r" })),
    ).toThrow(/usePresence needs/);
  });
});

describe("useAction", () => {
  it("tracks pending inputs, data and errors", async () => {
    let fail = false;
    const action = vi.fn(
      async (input: { id: number }): Promise<ActionResultOf<number>> =>
        fail
          ? { ok: false, data: null, error: dbError("conflict", "taken") }
          : { ok: true, data: input.id * 2, error: null },
    );
    const view = mount(null, () => useAction(action));
    const pending = view.result.run({ id: 2 });
    expect(view.result.pending).toBe(true);
    expect(view.result.pendingInput).toEqual({ id: 2 });
    expect(view.result.pendingInputs).toEqual([{ id: 2 }]);
    await pending;
    expect(view.result.data).toBe(4);
    fail = true;
    await view.result.run({ id: 3 });
    expect(view.result.error?.kind).toBe("conflict");
    view.result.reset();
    expect(view.result.error).toBeUndefined();
    view.dispose();
    expectTypeOf(view.result.run).parameter(0).toEqualTypeOf<{ id: number }>();
  });
});
