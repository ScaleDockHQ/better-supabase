import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, expectTypeOf, it, vi } from "vitest";
import {
  createApp,
  createSSRApp,
  defineComponent,
  effectScope,
  h,
  nextTick,
  ref,
  type App,
} from "vue";
import { renderToString } from "vue/server-renderer";

import type { AuthSession } from "../../src/auth/view.ts";
import type { ActionResultOf, ClientLike } from "../../src/bindings/client.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { defineTopic } from "../../src/realtime/index.ts";
import {
  betterSupabase,
  createBindings,
  provideSession,
  useAction,
  useAuth,
  useBroadcast,
  useLiveCount,
  useLiveQuery,
  usePresence,
  useSession,
  useSupabase,
  useSupportSession,
} from "../../src/vue/index.ts";
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

function withApp(
  client: ClientLike | null,
  queryClient?: NonNullable<
    Parameters<typeof betterSupabase>[1]
  >["queryClient"],
): App {
  const app = createApp({ render: () => null });
  if (client)
    app.use(
      betterSupabase(client, queryClient === undefined ? {} : { queryClient }),
    );
  return app;
}

/** Runs composables in an effect scope with the app's injections. */
function run<T>(app: App, setup: () => T): { result: T; stop: () => void } {
  const scope = effectScope();
  const result = app.runWithContext(() => scope.run(setup)!);
  return {
    result,
    stop: () => {
      scope.stop();
    },
  };
}

describe("betterSupabase plugin", () => {
  it("shares the auth state and resets queries when the user changes", async () => {
    const { browser, setAuth } = fakeBrowser(signedIn(USER));
    const { queryClient } = cachedClient(["bs", "customers"]);
    const reset = vi.spyOn(queryClient, "resetQueries");
    const app = withApp(browser, queryClient);
    const { result } = run(app, () => ({
      auth: useAuth(),
      supabase: useSupabase(),
    }));
    expect(result.auth.value.user?.id).toBe(USER);
    expect(result.supabase).toBe(browser.supabase);
    setAuth(signedIn(OTHER));
    expect(result.auth.value.user?.id).toBe(OTHER);
    expect(reset).toHaveBeenCalledOnce();
  });

  it("explains a missing plugin", () => {
    const app = withApp(null);
    expect(() => run(app, () => useAuth())).toThrow(
      /app.use\(betterSupabase\(bs\)\)/,
    );
  });

  it("types the composables with createBindings", () => {
    const { browser } = fakeBrowser(SIGNED_OUT);
    const app = withApp(browser);
    const bindings = createBindings<typeof browser>();
    const { result } = run(app, () => ({
      db: bindings.useDb(),
      queries: bindings.useQueries(),
    }));
    expect(result.db).toBe(browser.db);
    expect(result.queries).toBe(browser.queries);
  });

  it("does not subscribe while rendering on the server", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    const { queryClient } = cachedClient();
    const spec = typed.spec.notes.findMany();
    const app = createSSRApp(
      defineComponent({
        setup() {
          const status = useLiveQuery(spec);
          return () => h("span", status.value);
        },
      }),
    );
    app.use(betterSupabase(browser, { queryClient }));
    expect(await renderToString(app)).toBe("<span>closed</span>");
    expect(client.channel).not.toHaveBeenCalled();
  });
});

describe("provideSession and useSession", () => {
  it("reads the provided session and its support view", async () => {
    const session = ref({ user: { id: USER } } as unknown as AuthSession);
    const Child = defineComponent({
      setup() {
        const current = useSession();
        const support = useSupportSession();
        return () => {
          const value = current.value;
          const id = "user" in value ? value.user.id : undefined;
          return h("span", `${String(id)}:${String(support.value)}`);
        };
      },
    });
    const app = createSSRApp(
      defineComponent({
        setup() {
          provideSession(session);
          return () => h(Child);
        },
      }),
    );
    expect(await renderToString(app)).toBe(`<span>${USER}:undefined</span>`);
  });

  it("explains a missing session", () => {
    const app = withApp(null);
    expect(() => run(app, () => useSession())).toThrow(/provideSession/);
  });
});

describe("useBroadcast", () => {
  const anything: StandardSchemaV1<unknown, unknown> = {
    "~standard": {
      version: 1,
      vendor: "test",
      validate: (value) => ({ value }),
    },
  };
  const room = defineTopic("room:{roomId}", { events: { created: anything } });

  it("subscribes, forwards messages, pauses on null and resubscribes on a new user", async () => {
    const { browser, client, emit, setAuth } = fakeBrowser(LOADING);
    const cache = cachedClient(["bs", "customers"]);
    const app = withApp(browser, cache.queryClient);
    const roomId = ref<string | null>("r1");
    const created = vi.fn();
    const { result, stop } = run(app, () =>
      useBroadcast(
        room,
        () => (roomId.value ? { roomId: roomId.value } : null),
        { created },
        { invalidate: ["customers"] },
      ),
    );
    expect(client.channel).not.toHaveBeenCalled();
    setAuth(signedIn(USER));
    await nextTick();
    expect(client.channel).toHaveBeenCalledTimes(1);
    await flush();
    expect(result.value).toBe("subscribed");
    emit("room:r1", "created", {});
    await flush();
    expect(created).toHaveBeenCalledOnce();
    expect(cache.invalidated(["bs", "customers"])).toBe(true);

    setAuth(signedIn(OTHER));
    await nextTick();
    expect(client.channel).toHaveBeenCalledTimes(2);

    roomId.value = null;
    await nextTick();
    expect(result.value).toBe("closed");
    stop();
  });

  it("reports invalid messages and passes self", async () => {
    const { browser, client, emit } = fakeBrowser(signedIn(USER));
    const strict: StandardSchemaV1<unknown, unknown> = {
      "~standard": {
        version: 1,
        vendor: "test",
        validate: () => ({ issues: [{ message: "no" }] }),
      },
    };
    const checked = defineTopic("checked:{id}", {
      events: { created: strict },
    });
    const onInvalid = vi.fn();
    const app = withApp(browser);
    const { stop } = run(app, () =>
      useBroadcast(checked, { id: "c" }, {}, { self: true, onInvalid }),
    );
    expect(client.channel.mock.calls[0]![1]).toMatchObject({
      config: { broadcast: { self: true } },
    });
    emit("checked:c", "created", {});
    await flush();
    expect(onInvalid).toHaveBeenCalledOnce();
    stop();
  });

  it("invalidates the keys a function returns", async () => {
    const { browser, emit } = fakeBrowser(signedIn(USER));
    const cache = cachedClient(["bs", "x", 1]);
    const app = withApp(browser, cache.queryClient);
    const plain = defineTopic("plain:{id}");
    const { stop } = run(app, () =>
      useBroadcast(plain, { id: "p" }, undefined, {
        invalidate: () => [["bs", "x"]],
      }),
    );
    emit("plain:p", "anything");
    await flush();
    expect(cache.invalidated(["bs", "x", 1])).toBe(true);
    stop();
  });

  it("needs a query client for invalidate and a client without the plugin", () => {
    const { browser } = fakeBrowser(signedIn(USER));
    const app = withApp(browser);
    expect(() =>
      run(app, () =>
        useBroadcast(room, { roomId: "r" }, undefined, {
          invalidate: ["customers"],
        }),
      ),
    ).toThrow(/needs a queryClient/);
    expect(() =>
      run(withApp(null), () => useBroadcast(room, { roomId: "r" })),
    ).toThrow(/useBroadcast needs/);
  });

  it("follows a plain client's auth state without the plugin", async () => {
    const { client, emitAuth } = fakeBrowser(LOADING);
    const app = withApp(null);
    const { stop } = run(app, () =>
      useBroadcast(room, { roomId: "r" }, undefined, {
        client: client as never,
      }),
    );
    expect(client.channel).not.toHaveBeenCalled();
    emitAuth({ user: { id: USER }, access_token: "x" });
    await nextTick();
    expect(client.channel).toHaveBeenCalledOnce();
    stop();
  });
});

describe("useLiveQuery", () => {
  const spec = typed.spec.customers.findMany({ include: { notes: true } });

  it("needs a query client for a spec", () => {
    const { browser } = fakeBrowser(signedIn(USER));
    const app = withApp(browser);
    expect(run(app, () => useLiveQuery(null)).result.value).toBe("closed");
    expect(() => run(app, () => useLiveQuery(spec))).toThrow(
      /useLiveQuery needs/,
    );
  });

  it("watches with the claimed tenant, invalidates and rejoins", async () => {
    const { browser, client, emit, setAuth } = fakeBrowser(LOADING);
    const cache = cachedClient(["bs", "customers"], ["bs", "organizations"]);
    const app = withApp(browser, cache.queryClient);
    const current = ref<typeof spec | null>(spec);
    const { result, stop } = run(app, () =>
      useLiveQuery(current, { debounceMs: 1 }),
    );
    setAuth(signedIn(USER, { app_metadata: { tenant_id: "org-1" } }));
    await nextTick();
    expect(client.channel.mock.calls.map(([topic]) => topic)).toEqual([
      "bs:t:public.customers:org-1",
      "bs:t:public.notes",
    ]);
    await flush();
    expect(result.value).toBe("subscribed");
    emit("bs:t:public.customers:org-1", "change");
    await wait(10);
    expect(cache.invalidated(["bs", "customers"])).toBe(true);
    expect(cache.invalidated(["bs", "organizations"])).toBe(false);

    current.value = null;
    await wait(5);
    expect(client.removeChannel).toHaveBeenCalledTimes(2);
    current.value = spec;
    await nextTick();
    expect(client.channel).toHaveBeenCalledTimes(4);
    stop();
  });
});

describe("useLiveCount", () => {
  const spec = typed.spec.notes.count();

  it("counts, keeps the last count on errors and shows a seed first", async () => {
    const answers = [
      AsyncResult.ok(4),
      AsyncResult.err(dbError("network", "offline")),
    ];
    const run$ = vi.fn(() => answers.shift() ?? AsyncResult.ok(0));
    const { browser, emit } = fakeBrowser(signedIn(USER), { $run: run$ });
    const app = withApp(browser);
    const counted = run(app, () => useLiveCount(spec, { debounceMs: 1 }));
    expect(counted.result.count).toBeUndefined();
    await flush();
    expect(counted.result.count).toBe(4);
    expect(counted.result.status).toBe("subscribed");
    emit("bs:t:public.notes", "change");
    await wait(10);
    expect(counted.result.count).toBe(4);
    expect(counted.result.error?.kind).toBe("network");
    counted.stop();

    const seeded = run(app, () =>
      useLiveCount({ spec, count: 3 }, { debounceMs: 1 }),
    );
    await flush();
    expect(seeded.result.count).toBe(3);
    seeded.stop();
  });
});

describe("usePresence", () => {
  it("joins, tracks the state, re-tracks when it changes and leaves", async () => {
    const { browser, setAuth } = fakeBrowser(LOADING);
    const { topic, joins } = fakePresenceTopic();
    const app = withApp(browser);
    const roomId = ref<string | null>("r1");
    const name = ref<string | null>("Ada");
    const { result, stop } = run(app, () =>
      usePresence(
        topic,
        () => (roomId.value ? { roomId: roomId.value } : null),
        { state: () => (name.value === null ? null : { name: name.value }) },
      ),
    );
    expect(joins).toHaveLength(0);
    expect(await result.track({ name: "x" })).toMatchObject({
      kind: "invalid_request",
    });
    expect(await result.untrack()).toMatchObject({ kind: "invalid_request" });
    setAuth(signedIn(USER));
    await nextTick();
    expect(joins).toHaveLength(1);
    expect(result.status).toBe("subscribed");
    expect(joins[0]!.tracked).toEqual([{ name: "Ada" }]);
    joins[0]!.options.onPresence?.([{ key: "k", state: { name: "Ada" } }]);
    expect(result.members).toEqual([{ key: "k", state: { name: "Ada" } }]);

    name.value = "Grace";
    await nextTick();
    expect(joins[0]!.tracked).toEqual([{ name: "Ada" }, { name: "Grace" }]);
    name.value = null;
    await nextTick();
    expect(joins[0]!.untracked).toBe(1);
    expect(await result.track({ name: "Z" })).toBeUndefined();
    expect(await result.untrack()).toMatchObject({ kind: "network" });

    roomId.value = null;
    await nextTick();
    expect(joins[0]!.left).toBe(true);
    expect(result.members).toEqual([]);
    expect(result.status).toBe("closed");
    stop();
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
    const onSuccess = vi.fn();
    const onError = vi.fn();
    const app = withApp(null);
    const { result, stop } = run(app, () =>
      useAction(action, { onSuccess, onError }),
    );
    const pending = result.run({ id: 2 });
    expect(result.pending).toBe(true);
    expect(result.pendingInput).toEqual({ id: 2 });
    expect(result.pendingInputs).toEqual([{ id: 2 }]);
    await pending;
    expect(result.pending).toBe(false);
    expect(result.data).toBe(4);
    expect(onSuccess).toHaveBeenCalledWith(4, { id: 2 });

    fail = true;
    await result.run({ id: 3 });
    expect(result.error?.kind).toBe("conflict");
    expect(result.data).toBe(4);
    expect(onError).toHaveBeenCalledOnce();
    result.reset();
    expect(result.error).toBeUndefined();
    expect(result.data).toBeUndefined();

    action.mockRejectedValueOnce(new Error("boom"));
    await expect(result.run({ id: 1 })).rejects.toThrow("boom");
    expect(result.pending).toBe(false);
    stop();
    expectTypeOf(result.run).parameter(0).toEqualTypeOf<{ id: number }>();
  });
});
