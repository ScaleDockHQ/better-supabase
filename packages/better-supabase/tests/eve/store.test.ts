import { describe, expect, it } from "vitest";

import { createEveSessionStore } from "../../src/eve/store.ts";

function recorder(rows: Record<string, unknown[]> = {}) {
  const calls: { fn: string; args: readonly unknown[] }[] = [];

  const call = <T>(fn: string, args: readonly unknown[]): Promise<T[]> => {
    calls.push({ fn, args });

    // SAFETY: the test supplies rows of the shape the function returns.
    return Promise.resolve((rows[fn] ?? []) as T[]);
  };

  return { call, calls };
}

describe("createEveSessionStore", () => {
  it("wakes with the default delay", async () => {
    const { call, calls } = recorder();
    await createEveSessionStore(call).wake("s");
    expect(calls).toEqual([{ fn: "eve_session_wake", args: ["s", 2] }]);
  });

  it("maps a lease row", async () => {
    const { call } = recorder({
      eve_session_lease: [
        {
          session_id: "s",
          tenant_id: "t",
          principal_kind: null,
          principal_id: null,
          eve_version: "1",
          chat_id: null,
          record_type: null,
          record_id: null,
          run_id: "r",
          read_cursor: "4",
          status: "open",
          lease_id: "l",
        },
      ],
    });

    expect(await createEveSessionStore(call).lease("s")).toMatchObject({
      sessionId: "s",
      tenantId: "t",
      cursor: 4,
      leaseId: "l",
      principalId: undefined,
    });
  });

  it("resolves undefined when the lease is held", async () => {
    const { call } = recorder();
    expect(await createEveSessionStore(call).lease("s")).toBeUndefined();
  });

  it("passes the commit fields positionally", async () => {
    const { call, calls } = recorder({
      eve_session_commit: [{ eve_session_commit: true }],
    });

    const ok = await createEveSessionStore(call).commit({
      sessionId: "s",
      leaseId: "l",
      cursor: 3,
      status: "ended",
    });

    expect(ok).toBe(true);
    expect(calls[0]?.args).toEqual([
      "s",
      "l",
      3,
      null,
      null,
      null,
      null,
      null,
      null,
      "ended",
    ]);
  });

  it("lists behind and open sessions", async () => {
    const { call } = recorder({
      eve_sessions_behind: [{ session_id: "a" }],
      eve_open_sessions: [
        {
          session_id: "b",
          eve_version: null,
          tenant_id: null,
          principal_id: null,
          chat_id: null,
          run_id: null,
        },
      ],
    });

    const store = createEveSessionStore(call);
    expect(await store.behind()).toEqual(["a"]);
    expect((await store.open())[0]?.sessionId).toBe("b");
  });
});
