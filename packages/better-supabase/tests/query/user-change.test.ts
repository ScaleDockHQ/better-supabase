import { QueryClient } from "@tanstack/query-core";
import { describe, expect, it } from "vitest";

import {
  clearOnUserChange,
  type UserChangeSource,
} from "../../src/query/index.ts";

type Snapshot = ReturnType<UserChangeSource["current"]>;

function fakeAuth(initial: Snapshot) {
  let snapshot = initial;
  const listeners = new Set<() => void>();
  const auth: UserChangeSource = {
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    current: () => snapshot,
  };
  const set = (next: Snapshot) => {
    snapshot = next;
    for (const listener of listeners) listener();
  };
  return { auth, set, listeners };
}

const signedIn = (id: string): Snapshot => ({
  status: "signed-in",
  user: { id },
});
const signedOut: Snapshot = { status: "signed-out", user: null };

function seeded(): QueryClient {
  const client = new QueryClient();
  client.setQueryData(["bs", "customers", "findMany"], [{ id: "c1" }]);
  client.setQueryData(["other"], 1);
  return client;
}

const keys = (client: QueryClient) =>
  client
    .getQueryCache()
    .getAll()
    .map((query) => query.queryKey);

describe("clearOnUserChange", () => {
  it("removes bs queries when the user signs out or changes, and only those", () => {
    const client = seeded();
    const { auth, set } = fakeAuth(signedIn("u1"));
    clearOnUserChange(client, auth);

    set(signedIn("u1"));
    expect(keys(client)).toHaveLength(2);

    set(signedOut);
    expect(keys(client)).toEqual([["other"]]);

    client.setQueryData(["bs", "notes"], []);
    set(signedIn("u2"));
    expect(keys(client)).toEqual([["other"]]);
  });

  it("waits for a loaded session before taking the first user", () => {
    const client = seeded();
    const { auth, set } = fakeAuth({ status: "loading", user: null });
    clearOnUserChange(client, auth);
    set(signedIn("u1"));
    expect(keys(client)).toHaveLength(2);
    set(signedIn("u2"));
    expect(keys(client)).toEqual([["other"]]);
  });

  it("stops listening when the returned function runs", () => {
    const client = seeded();
    const { auth, set, listeners } = fakeAuth(signedIn("u1"));
    const stop = clearOnUserChange(client, auth);
    stop();
    expect(listeners.size).toBe(0);
    set(signedOut);
    expect(keys(client)).toHaveLength(2);
  });
});
