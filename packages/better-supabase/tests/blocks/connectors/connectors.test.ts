import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../../src/credentials/provider.ts";

import { createConnectors } from "../../../src/blocks/connectors/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const AT = "2026-01-01T00:00:00Z";
const CAPABILITIES = {
  userSubjects: true,
  authorization: false,
  revoke: true,
  inbound: false,
};
const REF = { provider: "vault", secret: "mcp:s1", scope: "user" };

const grantRow = (overrides: Record<string, unknown> = {}) => ({
  id: "g1",
  user_id: "u1",
  server_id: "s1",
  organization_id: "o1",
  credential_ref: REF,
  scopes: ["read"],
  expires_at: AT,
  granted_at: AT,
  revoked_at: null,
  ...overrides,
});

const serverRow = (overrides: Record<string, unknown> = {}) => ({
  id: "s1",
  organization_id: "o1",
  name: "GitHub",
  url: "https://mcp.example.com",
  transport: "http",
  auth_type: "oauth",
  credential_ref: null,
  scopes: ["read"],
  client_metadata: { client_name: "app" },
  enabled: true,
  grant: grantRow(),
  created_at: AT,
  updated_at: AT,
  ...overrides,
});

type Handler = (args: Record<string, unknown>) => unknown;

function fakeTransport(handlers: Record<string, Handler>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });
      const handler = handlers[fn];
      if (!handler) return Promise.reject(new Error(`unexpected ${fn}`));
      return Promise.resolve(handler(args));
    },
  };
  return { transport, calls };
}

function fakeCredentials() {
  const revoked: { ref: CredentialRef; subject: unknown }[] = [];
  const credentials: CredentialProvider = {
    apiVersion: 1,
    name: "fake",
    getToken: () => AsyncResult.ok({ token: "t", headers: {} }),
    capabilities: () => CAPABILITIES,
    revoke: (ref, options) => {
      revoked.push({ ref, subject: options.subject });
      return AsyncResult.ok(true);
    },
  };
  return { credentials, revoked };
}

describe("createConnectors", () => {
  it("maps servers and their grants", async () => {
    const { transport, calls } = fakeTransport({
      list_connector_servers: () => [
        serverRow(),
        serverRow({
          id: "s2",
          transport: "bogus",
          auth_type: "bogus",
          client_metadata: null,
          enabled: false,
          grant: null,
          credential_ref: { provider: "vault", secret: "k" },
          created_at: new Date(AT),
        }),
      ],
      get_connector: (args) => (args["id"] === "gone" ? null : serverRow()),
      save_connector_server: () => serverRow(),
    });
    const connectors = createConnectors({ transport });
    const [first, second] = await connectors.servers.list("o1").orThrow();
    expect(first?.grant?.credentialRef).toEqual(REF);
    expect(first?.grant?.expiresAt?.toString()).toBe(AT);
    expect(second).toMatchObject({
      transport: "http",
      authType: "none",
      clientMetadata: {},
      enabled: false,
      grant: undefined,
      credentialRef: { provider: "vault", secret: "k" },
    });
    const missing = await connectors.servers.get("gone");
    expect(missing.ok ? undefined : missing.error.hint).toBe(
      "CONNECTOR_NOT_FOUND",
    );
    await connectors.servers.create("o1", {
      name: "GitHub",
      url: "https://mcp.example.com",
      transport: "sse",
      authType: "header",
      credentialRef: { provider: "vault", secret: "k" },
      scopes: ["read"],
      clientMetadata: { client_name: "app" },
      enabled: true,
    });
    await connectors.servers.update("o1", "s1", { credentialRef: null });
    expect(calls.slice(-2).map(({ args }) => args)).toEqual([
      {
        tenant: "o1",
        id: undefined,
        fields: {
          name: "GitHub",
          url: "https://mcp.example.com",
          transport: "sse",
          auth_type: "header",
          credential_ref: { provider: "vault", secret: "k" },
          scopes: ["read"],
          client_metadata: { client_name: "app" },
          enabled: true,
        },
      },
      { tenant: "o1", id: "s1", fields: { credential_ref: null } },
    ]);
  });

  it("gets another user's grant with the service role", async () => {
    const user = fakeTransport({});
    const service = fakeTransport({ get_connector: () => serverRow() });
    const connectors = createConnectors({
      transport: user.transport,
      service: service.transport,
    });
    await connectors.servers.get("s1", { ownerId: "u2" });
    expect(user.calls).toEqual([]);
    expect(service.calls[0]?.args).toEqual({ id: "s1", owner: "u2" });
  });

  it("revokes credentials when grants go away", async () => {
    const { credentials, revoked } = fakeCredentials();
    const { transport } = fakeTransport({
      delete_connector_server: () => [
        grantRow(),
        grantRow({ id: "g2", user_id: "u2" }),
      ],
      revoke_connector_grant: (args) =>
        args["id"] === "g1" ? grantRow() : null,
      record_connector_grant: (args) =>
        args["owner"] === "u1"
          ? { grant: grantRow(), replaced: grantRow({ id: "g0" }) }
          : {
              grant: grantRow({ user_id: "u3" }),
              replaced: grantRow({
                id: "g0",
                user_id: "u3",
                credential_ref: { provider: "vercel-connect", connector: "gh" },
              }),
            },
    });
    const connectors = createConnectors({ transport, credentials });
    expect(await connectors.servers.remove("s1").orThrow()).toBe(2);
    expect(revoked.map(({ subject }) => subject)).toEqual([
      { type: "user", id: "u1" },
      { type: "user", id: "u2" },
    ]);
    expect(await connectors.grants.revoke("g1").orThrow()).toBe(true);
    expect(await connectors.grants.revoke("g9").orThrow()).toBe(false);
    expect(revoked).toHaveLength(3);

    // The same ref again is a reconnect; its secret holds the new token.
    await connectors.grants.record("s1", "u1", REF);
    expect(revoked).toHaveLength(3);
    await connectors.grants.record("s1", "u3", REF, {
      scopes: ["read"],
      expiresAt: Temporal.Instant.from(AT),
    });
    expect(revoked.at(-1)?.ref).toEqual({
      provider: "vercel-connect",
      connector: "gh",
    });
  });

  it("skips revocation without a credential provider", async () => {
    const { transport } = fakeTransport({
      delete_connector_server: () => [grantRow()],
      revoke_connector_grant: () => grantRow(),
    });
    const connectors = createConnectors({ transport });
    expect(await connectors.servers.remove("s1").orThrow()).toBe(1);
    expect(await connectors.grants.revoke("g1").orThrow()).toBe(true);
  });

  it("stops at the first credential that fails to revoke", async () => {
    const credentials: CredentialProvider = {
      apiVersion: 1,
      name: "broken",
      getToken: () => AsyncResult.ok({ token: "t", headers: {} }),
      capabilities: () => CAPABILITIES,
      revoke: () =>
        AsyncResult.err({ kind: "network", message: "down" } as never),
    };
    const { transport } = fakeTransport({
      delete_connector_server: () => [grantRow()],
    });
    const removed = await createConnectors({
      transport,
      credentials,
    }).servers.remove("s1");
    expect(removed.ok).toBe(false);
  });

  it("rejects a grant row without a ref", async () => {
    const { transport } = fakeTransport({
      expiring_connector_grants: () => [grantRow({ credential_ref: null })],
    });
    const result = await createConnectors({ transport }).grants.expiring(
      Temporal.Instant.from(AT),
    );
    expect(result.ok ? undefined : result.error.message).toContain(
      "without a ref",
    );
  });

  it("renews, keeps sessions and checks fingerprints", async () => {
    const { transport, calls } = fakeTransport({
      expiring_connector_grants: () => [grantRow()],
      renew_connector_grant: () => true,
      get_connector_session: (args) =>
        args["chat_key"] === "c1"
          ? {
              session_id: "sess",
              initialize_result: { protocolVersion: "2025-11-25" },
              expires_at: AT,
            }
          : null,
      save_connector_session: () => true,
      purge_connector_sessions: () => 4,
      check_connector_fingerprint: (args) =>
        args["fingerprint"] === "new" ? "bogus" : "approved",
      decide_connector_fingerprint: () => true,
    });
    const connectors = createConnectors({ transport });
    const at = Temporal.Instant.from(AT);
    expect(
      await connectors.grants.expiring(at, { limit: 3 }).orThrow(),
    ).toHaveLength(1);
    expect(await connectors.grants.renew("g1", at).orThrow()).toBe(true);
    expect(await connectors.sessions.get("s1", "c1").orThrow()).toEqual({
      sessionId: "sess",
      initializeResult: { protocolVersion: "2025-11-25" },
      expiresAt: at,
    });
    expect(await connectors.sessions.get("s1").orThrow()).toBeUndefined();
    await connectors.sessions.save("s1", { sessionId: "sess" });
    await connectors.sessions.forget("s1", "c1");
    expect(await connectors.sessions.purge().orThrow()).toBe(4);
    expect(await connectors.fingerprints.check("s1", "old").orThrow()).toBe(
      "approved",
    );
    expect(await connectors.fingerprints.check("s1", "new", {}).orThrow()).toBe(
      "pending",
    );
    await connectors.fingerprints.approve("s1", "new");
    await connectors.fingerprints.reject("s1", "new");
    expect(
      calls
        .filter(({ fn }) =>
          ["save_connector_session", "decide_connector_fingerprint"].includes(
            fn,
          ),
        )
        .map(({ args }) => args),
    ).toEqual([
      {
        server_id: "s1",
        chat_key: "",
        session_id: "sess",
        initialize_result: undefined,
      },
      { server_id: "s1", chat_key: "c1" },
      { server_id: "s1", fingerprint: "new", approved: true },
      { server_id: "s1", fingerprint: "new", approved: false },
    ]);
  });
});
