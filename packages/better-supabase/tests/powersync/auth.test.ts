import { describe, expect, it, vi } from "vitest";

import type { AuthSnapshot } from "../../src/client/bind.ts";

import { syncWithAuth } from "../../src/powersync/auth.ts";

const LOADING: AuthSnapshot = { status: "loading", user: null, claims: null };
const SIGNED_OUT: AuthSnapshot = {
  status: "signed-out",
  user: null,
  claims: null,
};
const signedIn = (id: string): AuthSnapshot => ({
  status: "signed-in",
  user: { id },
  claims: { sub: id },
});

function fakeAuth(initial: AuthSnapshot) {
  let snapshot = initial;
  const listeners = new Set<() => void>();
  return {
    auth: {
      current: () => snapshot,
      subscribe: (listener: () => void) => {
        listeners.add(listener);
        return () => void listeners.delete(listener);
      },
    },
    listeners,
    set: (next: AuthSnapshot) => {
      snapshot = next;
      for (const listener of [...listeners]) listener();
    },
  };
}

function fakeDb() {
  const steps: string[] = [];
  const step = (name: string) =>
    vi.fn(async () => {
      steps.push(name);
    });
  return {
    steps,
    db: {
      connect: step("connect"),
      disconnect: step("disconnect"),
      disconnectAndClear: step("clear"),
    },
  };
}

const flush = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

describe("syncWithAuth", () => {
  it("connects on sign-in and clears on sign-out and on a user change", async () => {
    const { auth, set, listeners } = fakeAuth(LOADING);
    const { db, steps } = fakeDb();
    const stop = syncWithAuth(db, auth, { connector: "connector" });
    set(signedIn("a"));
    set(signedIn("a"));
    set(signedIn("b"));
    set(SIGNED_OUT);
    await flush();
    expect(steps).toEqual(["connect", "clear", "connect", "clear"]);
    expect(db.connect).toHaveBeenCalledWith("connector");
    stop();
    set(signedIn("c"));
    await flush();
    expect(steps.at(-1)).toBe("disconnect");
    expect(listeners.size).toBe(0);
  });

  it("clears rows left from an earlier session when the app starts signed out", async () => {
    const { auth } = fakeAuth(SIGNED_OUT);
    const { db, steps } = fakeDb();
    syncWithAuth(db, auth, { connector: null });
    await flush();
    expect(steps).toEqual(["clear"]);
  });

  it("only disconnects without clearOnSignOut and reports failed steps", async () => {
    const { auth, set } = fakeAuth(signedIn("a"));
    const { db, steps } = fakeDb();
    const onError = vi.fn();
    db.connect.mockRejectedValueOnce(new Error("offline"));
    syncWithAuth(db, auth, { connector: null, clearOnSignOut: false, onError });
    set(SIGNED_OUT);
    await flush();
    expect(onError).toHaveBeenCalledWith(new Error("offline"));
    expect(steps).toEqual(["disconnect"]);
    const fresh = fakeDb();
    syncWithAuth(fresh.db, fakeAuth(SIGNED_OUT).auth, {
      connector: null,
      clearOnSignOut: false,
    });
    await flush();
    expect(fresh.steps).toEqual([]);
  });
});
