import type { Session } from "@supabase/supabase-js";

import { describe, expect, it, vi } from "vitest";

import {
  callerOf,
  countSource,
  createActionRunner,
  joinPresence,
  keyed,
  NO_COUNT,
  plainCaller,
  shownCount,
} from "../../src/bindings/client.ts";
import { sessionUserId } from "../../src/bindings/keys.ts";
import {
  fakePresenceTopic,
  fakeRealtime,
  signedIn,
  typed,
  USER,
} from "../fixtures/fake-browser.ts";

const token = (payload: Record<string, unknown>) =>
  `x.${Buffer.from(JSON.stringify(payload)).toString("base64url")}.y`;

describe("sessionUserId", () => {
  it("reads the user, or the token's sub behind a tokens-only placeholder", () => {
    expect(sessionUserId({ user: { id: USER } } as Session)).toBe(USER);
    const placeholder = {
      get user(): never {
        throw new Error("tokens-only");
      },
      access_token: token({ sub: "from-token" }),
    } as unknown as Session;
    expect(sessionUserId(placeholder)).toBe("from-token");
    expect(
      sessionUserId({
        user: {},
        access_token: token({}),
      } as unknown as Session),
    ).toBeNull();
  });
});

describe("plainCaller", () => {
  it("follows the client's auth state and stops listening", () => {
    const realtime = fakeRealtime();
    const caller = plainCaller(realtime.client as never);
    expect(caller.current()).toEqual({ status: "loading", userId: null });
    const listener = vi.fn();
    const stop = caller.subscribe(listener);
    realtime.emitAuth(null);
    expect(caller.current()).toEqual({ status: "signed-out", userId: null });
    realtime.emitAuth({ user: { id: USER }, access_token: "x" });
    expect(caller.current()).toEqual({ status: "signed-in", userId: USER });
    expect(listener).toHaveBeenCalledTimes(2);
    stop();
    expect(realtime.authListeners.size).toBe(0);
    expect(callerOf(signedIn(USER))).toEqual({
      status: "signed-in",
      userId: USER,
    });
  });
});

describe("keyed", () => {
  it("restarts on a new key, keeps the run on the same key and stops on null", () => {
    const run = keyed();
    const stops: string[] = [];
    const start = (key: string) => () => () => void stops.push(key);
    run.update("a", start("a"));
    run.update("a", start("a2"));
    run.update("b", start("b"));
    expect(stops).toEqual(["a"]);
    run.update(null, () => undefined);
    expect(stops).toEqual(["a", "b"]);
    run.update("c", () => undefined);
    run.stop();
    run.stop();
    expect(stops).toEqual(["a", "b"]);
  });
});

describe("countSource and shownCount", () => {
  const spec = typed.spec.notes.count();

  it("splits seeds from specs and prefers a newer seed", () => {
    expect(countSource(null, {})).toEqual({
      spec: null,
      initial: undefined,
      seedAt: undefined,
      seeded: false,
    });
    expect(countSource(spec, { initial: 2 }).initial).toBe(2);
    const seeded = countSource({ spec, count: 5, at: 100 }, {});
    expect(seeded).toMatchObject({
      spec,
      initial: 5,
      seedAt: 100,
      seeded: true,
    });
    expect(
      shownCount({ key: "k", count: 1, at: 50, error: undefined }, "k", seeded),
    ).toEqual({ count: 5, error: undefined });
    expect(
      shownCount(
        { key: "k", count: 1, at: 150, error: undefined },
        "k",
        seeded,
      ),
    ).toEqual({ count: 1, error: undefined });
    expect(shownCount(NO_COUNT, "other", seeded).count).toBe(5);
  });
});

describe("joinPresence", () => {
  it("returns nothing for a name the topic does not match", () => {
    const { topic } = fakePresenceTopic();
    expect(
      joinPresence({} as never, topic, "elsewhere", {
        onStatus: () => undefined,
        onPresence: () => undefined,
      }),
    ).toBeUndefined();
  });
});

describe("createActionRunner", () => {
  it("keeps two runs with equal inputs apart and stops notifying", async () => {
    const resolvers: (() => void)[] = [];
    const runner = createActionRunner(() => ({
      action: (input: number) =>
        new Promise<{ ok: true; data: number; error: null }>((resolve) => {
          resolvers.push(() => {
            resolve({ ok: true, data: input, error: null });
          });
        }),
      options: {},
    }));
    const listener = vi.fn();
    const stop = runner.subscribe(listener);
    const first = runner.run(1);
    const second = runner.run(1);
    expect(runner.current().pendingInputs).toEqual([1, 1]);
    resolvers[0]!();
    await first;
    expect(runner.current().pendingInputs).toEqual([1]);
    stop();
    resolvers[1]!();
    await second;
    expect(runner.current().pending).toBe(false);
    expect(listener).toHaveBeenCalledTimes(3);
  });
});
