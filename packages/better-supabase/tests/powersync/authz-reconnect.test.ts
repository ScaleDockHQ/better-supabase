import { describe, expect, it } from "vitest";

import type { AuthSnapshot } from "../../src/client/bind.ts";

import { syncWithAuth } from "../../src/powersync/auth.ts";
import { createUploadConnector } from "../../src/powersync/connector.ts";

/**
 * A sync service that, like PowerSync, evaluates its rules once per connection:
 * the user's roles and active tenant are read from the database when the stream
 * opens, and the checkpoint replaces the local rows.
 */
function fakeService() {
  const rows = [
    { id: "acme-public", tenant: "acme", role: "member" },
    { id: "acme-payroll", tenant: "acme", role: "admin" },
    { id: "globex-public", tenant: "globex", role: "member" },
  ];

  const roles = new Map<string, Map<string, string>>([
    [
      "u1",
      new Map([
        ["acme", "admin"],
        ["globex", "member"],
      ]),
    ],
  ]);

  const activeTenant = new Map([["u1", "acme"]]);

  return {
    roles,
    activeTenant,
    checkpoint(token: string): string[] {
      // SAFETY: the fake tokens below are JSON claims.
      const { sub } = JSON.parse(token) as { sub: string };
      const tenant = activeTenant.get(sub);
      const role = tenant ? roles.get(sub)?.get(tenant) : undefined;

      return rows
        .filter(
          (row) =>
            row.tenant === tenant &&
            (role === "admin" || (role === "member" && row.role === "member")),
        )
        .map((row) => row.id);
    },
  };
}

function fakeSession() {
  let claims: Record<string, unknown> | null = { sub: "u1", authz_ver: 1 };
  const listeners = new Set<() => void>();

  const snapshot = (): AuthSnapshot =>
    claims
      ? { status: "signed-in", user: { id: "u1" }, claims }
      : { status: "signed-out", user: null, claims: null };

  return {
    auth: {
      current: snapshot,
      subscribe: (listener: () => void) => {
        listeners.add(listener);

        return () => void listeners.delete(listener);
      },
    },
    supabase: {
      auth: {
        getSession: async () => ({
          data: {
            session: claims ? { access_token: JSON.stringify(claims) } : null,
          },
        }),
      },
    },
    /** A token refresh, as the client's `onAuthStateChange` reports it. */
    refresh(next: Record<string, unknown> | null) {
      claims = next;

      for (const listener of [...listeners]) {
        listener();
      }
    },
  };
}

interface Connector {
  fetchCredentials(): Promise<{ readonly token: string } | null>;
}

function fakeDatabase(service: ReturnType<typeof fakeService>) {
  const state = { rows: [] as string[], connected: false, connects: 0 };
  let gate: Promise<void> = Promise.resolve();

  return {
    state,
    hold() {
      let release = () => {};

      gate = new Promise((resolve) => {
        release = resolve;
      });

      return () => {
        release();
      };
    },
    db: {
      async connect(connector: Connector) {
        state.connects += 1;
        await gate;
        const credentials = await connector.fetchCredentials();

        if (!credentials) {
          return;
        }

        state.rows = service.checkpoint(credentials.token);
        state.connected = true;
      },
      async disconnect() {
        state.connected = false;
      },
      async disconnectAndClear() {
        state.connected = false;
        state.rows = [];
      },
    },
  };
}

const settle = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

function setup() {
  const service = fakeService();
  const session = fakeSession();
  const local = fakeDatabase(service);

  const connector = createUploadConnector({
    endpoint: "https://sync.example",
    supabase: session.supabase,
    tables: {},
  });

  const sync = syncWithAuth(local.db, session.auth, { connector });

  return { service, session, local, sync };
}

describe("PowerSync after an authorization change", () => {
  it("drops revoked rows once the refreshed token reconnects", async () => {
    const { service, session, local } = setup();
    await settle();
    expect(local.state.rows).toEqual(["acme-public", "acme-payroll"]);

    service.roles.get("u1")?.set("acme", "member");
    await settle();
    expect(local.state.rows).toContain("acme-payroll");

    session.refresh({ sub: "u1", authz_ver: 2 });
    await settle();
    expect(local.state.rows).toEqual(["acme-public"]);
    expect(local.state.connects).toBe(2);
  });

  it("does not reconnect when a refresh keeps the fingerprint", async () => {
    const { session, local } = setup();
    await settle();
    session.refresh({ sub: "u1", authz_ver: 1, iat: 2 });
    await settle();
    expect(local.state.connects).toBe(1);
  });

  it("switches tenant through reconnect()", async () => {
    const { service, local, sync } = setup();
    await settle();
    service.activeTenant.set("u1", "globex");
    await sync.reconnect();
    expect(local.state.rows).toEqual(["globex-public"]);
  });

  it("clears after a sign-out that lands during a reconnect", async () => {
    const { session, local, sync } = setup();
    await settle();
    const release = local.hold();
    const reconnecting = sync.reconnect();
    await settle();
    session.refresh(null);
    release();
    await reconnecting;
    await settle();
    expect(local.state).toMatchObject({ rows: [], connected: false });
  });
});
