import { QueryClient, QueryObserver } from "@tanstack/query-core";
import { describe, expect, it, vi } from "vitest";

import {
  clearOnUserChange,
  type UserChangeSource,
} from "../../src/query/index.ts";
import { identityKey } from "../../src/query/user-change.ts";

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

const signedIn = (
  id: string,
  claims: Record<string, unknown> = {},
): Snapshot => ({
  status: "signed-in",
  user: { id },
  claims: { sub: id, exp: 1000, iat: 900, ...claims },
});
const signedOut: Snapshot = { status: "signed-out", user: null };

const BS_KEY = ["bs", "customers", "findMany"];

function seeded(): QueryClient {
  const client = new QueryClient();
  client.setQueryData(BS_KEY, [{ id: "c1" }]);
  client.setQueryData(["other"], 1);
  return client;
}

const bsData = (client: QueryClient) => client.getQueryData(BS_KEY);

describe("clearOnUserChange", () => {
  it("resets bs queries when the user signs out or changes, and only those", () => {
    const client = seeded();
    const { auth, set } = fakeAuth(signedIn("u1"));
    clearOnUserChange(client, auth);

    set(signedIn("u1"));
    expect(bsData(client)).toEqual([{ id: "c1" }]);

    set(signedOut);
    expect(bsData(client)).toBeUndefined();
    expect(client.getQueryData(["other"])).toBe(1);

    client.setQueryData(BS_KEY, [{ id: "c2" }]);
    set(signedIn("u2"));
    expect(bsData(client)).toBeUndefined();
  });

  it("keeps rows across a token refresh and resets them on an organization switch", () => {
    const client = seeded();
    const { auth, set } = fakeAuth(signedIn("u1", { tenant_id: "acme" }));
    clearOnUserChange(client, auth);

    set(signedIn("u1", { tenant_id: "acme", exp: 2000, iat: 1900 }));
    expect(bsData(client)).toEqual([{ id: "c1" }]);

    set(signedIn("u1", { tenant_id: "globex", exp: 3000 }));
    expect(bsData(client)).toBeUndefined();
  });

  it("refetches a mounted query instead of leaving the old rows on screen", async () => {
    const client = seeded();
    let calls = 0;
    const observer = new QueryObserver(client, {
      queryKey: BS_KEY,
      queryFn: () => {
        calls += 1;
        return [{ id: "fresh" }];
      },
      staleTime: Infinity,
    });
    const unsubscribe = observer.subscribe(() => undefined);
    const { auth, set } = fakeAuth(signedIn("u1", { tenant_id: "acme" }));
    clearOnUserChange(client, auth);
    set(signedIn("u1", { tenant_id: "globex" }));
    await vi.waitFor(() => {
      expect(bsData(client)).toBeDefined();
    });
    expect(calls).toBe(1);
    expect(bsData(client)).toEqual([{ id: "fresh" }]);
    unsubscribe();
  });

  it("waits for a loaded session before taking the first user", () => {
    const client = seeded();
    const { auth, set } = fakeAuth({ status: "loading", user: null });
    clearOnUserChange(client, auth);
    set(signedIn("u1"));
    expect(bsData(client)).toEqual([{ id: "c1" }]);
    set(signedIn("u2"));
    expect(bsData(client)).toBeUndefined();
  });

  it("stops listening when the returned function runs", () => {
    const client = seeded();
    const { auth, set, listeners } = fakeAuth(signedIn("u1"));
    const stop = clearOnUserChange(client, auth);
    stop();
    expect(listeners.size).toBe(0);
    set(signedOut);
    expect(bsData(client)).toEqual([{ id: "c1" }]);
  });
});

describe("identityKey", () => {
  it("ignores the time claims and the claim order", () => {
    expect(identityKey(signedIn("u1", { role: "a", aal: "aal1" }))).toBe(
      identityKey({
        status: "signed-in",
        user: { id: "u1" },
        claims: { aal: "aal1", exp: 5, role: "a", sub: "u1", jti: "x" },
      }),
    );
    expect(identityKey(signedIn("u1", { aal: "aal1" }))).not.toBe(
      identityKey(signedIn("u1", { aal: "aal2" })),
    );
    expect(identityKey(signedOut)).toBeNull();
  });
});
