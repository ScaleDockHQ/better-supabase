import type { StandardSchemaV1 } from "@standard-schema/spec";

import * as $ from "svelte/internal/client";
import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { AuthSession } from "../../src/auth/view.ts";
import type { ActionResultOf } from "../../src/bindings/client.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { defineTopic } from "../../src/realtime/index.ts";
import {
  createBetterSvelte,
  getBetterSupabase,
  setBetterSupabase,
  setSession,
  useAction,
  useAuth,
  useBroadcast,
  useLiveCount,
  useLiveQuery,
  usePresence,
  useSession,
} from "../../src/svelte/index.ts";
import {
  cachedClient,
  fakeBrowser,
  fakePresenceTopic,
  flush,
  LOADING,
  OTHER,
  signedIn,
  typed,
  USER,
  wait,
} from "../fixtures/fake-browser.ts";

// Node resolves svelte to its server runtime, where effects never run.
vi.mock("svelte", () => {
  const clientBuild = "../../node_modules/svelte/src/index-client.js";
  return import(clientBuild);
});
vi.mock("svelte/reactivity", () => {
  const clientBuild =
    "../../node_modules/svelte/src/reactivity/index-client.js";
  return import(clientBuild);
});

/** Reads `read` in a render effect, as a template would, until `stop`. */
function observe<T>(read: () => T): { last: () => T; stop: () => void } {
  let last: T | undefined;
  const stop = $.effect_root(() => {
    $.render_effect(() => {
      last = read();
    });
  });
  $.flush();
  // SAFETY: the render effect ran once in flush.
  return { last: () => last as T, stop };
}

/** Settles queued notifications and the effects they schedule. */
async function settle(): Promise<void> {
  await flush();
  $.flush();
}

/** Runs `setup` as a component's script would, with a component context. */
function inComponent<T>(setup: () => T): T {
  let result: T | undefined;
  $.effect_root(() => {
    $.push({}, true);
    result = setup();
    $.pop();
  });
  $.flush();
  // SAFETY: setup ran inside the effect root.
  return result as T;
}

const anything: StandardSchemaV1<unknown, unknown> = {
  "~standard": { version: 1, vendor: "test", validate: (value) => ({ value }) },
};

describe("setBetterSupabase", () => {
  it("binds the client for the component and resets queries on a new user", async () => {
    const { browser, setAuth } = fakeBrowser(signedIn(USER));
    const { queryClient } = cachedClient(["bs", "customers"]);
    const reset = vi.spyOn(queryClient, "resetQueries");
    const bound = inComponent(() => {
      setBetterSupabase(browser, { queryClient });
      return { bs: getBetterSupabase(), auth: useAuth() };
    });
    expect(bound.bs.db).toBe(browser.db);
    expect(bound.bs.queries).toBe(browser.queries);
    expect(bound.bs.supabase).toBe(browser.supabase);
    const auth = observe(() => bound.auth.current.user?.id);
    expect(auth.last()).toBe(USER);
    setAuth(signedIn(OTHER));
    $.flush();
    expect(auth.last()).toBe(OTHER);
    expect(reset).toHaveBeenCalledOnce();
    auth.stop();
  });

  it("explains a missing binding and a missing session", () => {
    expect(() => inComponent(() => getBetterSupabase())).toThrow(
      /setBetterSupabase\(bs\)/,
    );
    expect(() => inComponent(() => useSession())).toThrow(/setSession/);
  });

  it("shares a session", () => {
    const session = { user: { id: USER } } as unknown as AuthSession;
    const current = inComponent(() => {
      setSession(() => session);
      return useSession();
    });
    expect(current.current).toBe(session);
  });

  it("gives the use helpers the bound client", () => {
    const { browser } = fakeBrowser(signedIn(USER));
    const { queryClient } = cachedClient();
    const { topic } = fakePresenceTopic();
    const room = defineTopic("room:{roomId}");
    const helpers = inComponent(() => {
      setBetterSupabase(browser, { queryClient });
      return [
        useBroadcast(room, () => null),
        useLiveQuery(() => null),
        useLiveCount(() => null),
        usePresence(topic, () => null),
        useAction(async () => ({ ok: true, data: 1, error: null }) as const),
      ] as const;
    });
    expect(helpers[0].current).toBe("closed");
    expect(helpers[1].current).toBe("closed");
    expect(helpers[2].count).toBeUndefined();
    expect(helpers[3].members).toEqual([]);
    expect(helpers[4].pending).toBe(false);
  });
});

describe("broadcast", () => {
  const room = defineTopic("room:{roomId}", { events: { created: anything } });

  it("subscribes while read, pauses on null, resubscribes on a new user and stops unread", async () => {
    const { browser, client, emit, setAuth } = fakeBrowser(LOADING);
    const cache = cachedClient(["bs", "customers"]);
    const bs = createBetterSvelte(browser, { queryClient: cache.queryClient });
    const roomId = $.state<string | null>("r1");
    const created = vi.fn();
    const status = bs.broadcast(
      room,
      () => {
        const id = $.get(roomId);
        return id ? { roomId: id } : null;
      },
      { created },
      { invalidate: ["customers"] },
    );
    expect(status.current).toBe("closed");
    expect(client.channel).not.toHaveBeenCalled();
    const view = observe(() => status.current);
    setAuth(signedIn(USER));
    $.flush();
    expect(client.channel).toHaveBeenCalledTimes(1);
    await settle();
    expect(view.last()).toBe("subscribed");
    emit("room:r1", "created", {});
    await flush();
    expect(created).toHaveBeenCalledOnce();
    expect(cache.invalidated(["bs", "customers"])).toBe(true);

    setAuth(signedIn(OTHER));
    $.flush();
    expect(client.channel).toHaveBeenCalledTimes(2);
    $.set(roomId, null);
    $.flush();
    await settle();
    expect(view.last()).toBe("closed");
    view.stop();
    await wait(5);
    expect(client.channel).toHaveBeenCalledTimes(2);
  });

  it("follows a plain client's auth and needs a query client to invalidate", async () => {
    const { browser, client, emitAuth } = fakeBrowser(LOADING);
    const bs = createBetterSvelte(browser);
    expect(() =>
      bs.broadcast(room, () => ({ roomId: "r" }), undefined, {
        invalidate: ["customers"],
      }),
    ).toThrow(/needs a queryClient/);
    const status = bs.broadcast(room, () => ({ roomId: "r" }), undefined, {
      client: client as never,
    });
    const view = observe(() => status.current);
    emitAuth({ user: { id: USER }, access_token: "x" });
    $.flush();
    expect(client.channel).toHaveBeenCalledOnce();
    view.stop();
  });
});

describe("liveQuery", () => {
  const spec = typed.spec.customers.findMany({ include: { notes: true } });

  it("watches with the claimed tenant, invalidates and rejoins", async () => {
    const { browser, client, emit, setAuth } = fakeBrowser(LOADING);
    const cache = cachedClient(["bs", "customers"], ["bs", "organizations"]);
    const bs = createBetterSvelte(browser, { queryClient: cache.queryClient });
    const current = $.state<typeof spec | null>(spec);
    const live = bs.liveQuery(() => $.get(current), { debounceMs: 1 });
    const view = observe(() => live.current);
    setAuth(signedIn(USER, { app_metadata: { tenant_id: "org-1" } }));
    $.flush();
    expect(client.channel.mock.calls.map(([topic]) => topic)).toEqual([
      "bs:t:public.customers:org-1",
      "bs:t:public.notes",
    ]);
    await settle();
    expect(view.last()).toBe("subscribed");
    emit("bs:t:public.customers:org-1", "change");
    await wait(10);
    expect(cache.invalidated(["bs", "customers"])).toBe(true);
    expect(cache.invalidated(["bs", "organizations"])).toBe(false);
    $.set(current, null);
    $.flush();
    await wait(5);
    expect(client.removeChannel).toHaveBeenCalledTimes(2);
    $.set(current, spec);
    $.flush();
    expect(client.channel).toHaveBeenCalledTimes(4);
    view.stop();
  });

  it("needs a query client for a spec", () => {
    const { browser } = fakeBrowser(signedIn(USER));
    const live = createBetterSvelte(browser).liveQuery(() => spec);
    expect(() => observe(() => live.current)).toThrow(/liveQuery needs/);
  });
});

describe("liveCount", () => {
  const spec = typed.spec.notes.count();

  it("counts, keeps the last count on errors and shows a seed first", async () => {
    const answers = [
      AsyncResult.ok(4),
      AsyncResult.err(dbError("network", "offline")),
    ];
    const run = vi.fn(() => answers.shift() ?? AsyncResult.ok(0));
    const { browser, emit } = fakeBrowser(signedIn(USER), { $run: run });
    const bs = createBetterSvelte(browser);
    const counted = bs.liveCount(() => spec, { debounceMs: 1 });
    const view = observe(() => ({
      count: counted.count,
      status: counted.status,
      error: counted.error,
    }));
    expect(view.last().count).toBeUndefined();
    await settle();
    await settle();
    expect(view.last()).toEqual({
      count: 4,
      status: "subscribed",
      error: undefined,
    });
    emit("bs:t:public.notes", "change");
    await wait(10);
    $.flush();
    expect(view.last().count).toBe(4);
    expect(view.last().error?.kind).toBe("network");
    view.stop();

    const seeded = bs.liveCount(() => ({ spec, count: 3 }), { debounceMs: 1 });
    const shown = observe(() => seeded.count);
    await settle();
    expect(shown.last()).toBe(3);
    shown.stop();
  });
});

describe("presence", () => {
  it("joins, tracks the state, re-tracks when it changes and leaves", async () => {
    const { browser, setAuth } = fakeBrowser(LOADING);
    const { topic, joins } = fakePresenceTopic();
    const bs = createBetterSvelte(browser);
    const roomId = $.state<string | null>("r1");
    const name = $.state<string | null>("Ada");
    const room = bs.presence(
      topic,
      () => {
        const id = $.get(roomId);
        return id ? { roomId: id } : null;
      },
      {
        state: () => {
          const current = $.get(name);
          return current === null ? null : { name: current };
        },
      },
    );
    expect(await room.track({ name: "x" })).toMatchObject({
      kind: "invalid_request",
    });
    expect(await room.untrack()).toMatchObject({ kind: "invalid_request" });
    const view = observe(() => ({
      members: room.members,
      status: room.status,
    }));
    expect(joins).toHaveLength(0);
    setAuth(signedIn(USER));
    $.flush();
    expect(joins).toHaveLength(1);
    await settle();
    expect(view.last().status).toBe("subscribed");
    expect(joins[0]!.tracked).toEqual([{ name: "Ada" }]);
    joins[0]!.options.onPresence?.([{ key: "k", state: { name: "Ada" } }]);
    await settle();
    expect(view.last().members).toEqual([{ key: "k", state: { name: "Ada" } }]);

    $.set(name, "Grace");
    $.flush();
    expect(joins[0]!.tracked).toEqual([{ name: "Ada" }, { name: "Grace" }]);
    $.set(name, null);
    $.flush();
    expect(joins[0]!.untracked).toBe(1);
    expect(await room.track({ name: "Z" })).toBeUndefined();
    expect(await room.untrack()).toMatchObject({ kind: "network" });

    $.set(roomId, null);
    $.flush();
    await settle();
    expect(joins[0]!.left).toBe(true);
    expect(view.last()).toEqual({ members: [], status: "closed" });
    view.stop();
  });
});

describe("action", () => {
  it("tracks pending inputs, data and errors reactively", async () => {
    let fail = false;
    const action = vi.fn(
      async (input: { id: number }): Promise<ActionResultOf<number>> =>
        fail
          ? { ok: false, data: null, error: dbError("conflict", "taken") }
          : { ok: true, data: input.id * 2, error: null },
    );
    const { browser } = fakeBrowser(signedIn(USER));
    const handle = createBetterSvelte(browser).action(action);
    const view = observe(() => ({
      pending: handle.pending,
      inputs: handle.pendingInputs,
      input: handle.pendingInput,
      data: handle.data,
      error: handle.error,
    }));
    const pending = handle.run({ id: 2 });
    $.flush();
    expect(view.last()).toMatchObject({
      pending: true,
      inputs: [{ id: 2 }],
      input: { id: 2 },
    });
    await pending;
    $.flush();
    expect(view.last().data).toBe(4);
    fail = true;
    await handle.run({ id: 3 });
    $.flush();
    expect(view.last().error?.kind).toBe("conflict");
    handle.reset();
    $.flush();
    expect(view.last().error).toBeUndefined();
    view.stop();
    expectTypeOf(handle.run).parameter(0).toEqualTypeOf<{ id: number }>();
  });
});
