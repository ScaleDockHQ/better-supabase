import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { accessTokenResolver } from "../../../src/auth/access-token.ts";
import { createOauthServer } from "../../../src/blocks/oauth-server/oauth-server.ts";

const sha256 = async (value: string): Promise<string> =>
  [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
  ]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

const fake = (answers: Record<string, unknown>) => {
  const call = vi.fn<BlockTransport["call"]>(
    async (_schema, fn) => answers[fn],
  );

  return { call, transport: { call } satisfies BlockTransport };
};

const CLIENT_ROW = {
  clientId: "bsc_client",
  name: "CLI",
  redirectUris: [],
  grantTypes: ["urn:ietf:params:oauth:grant-type:device_code"],
  tokenEndpointAuthMethod: "none",
  scope: "contacts:read",
  metadata: {},
  createdBy: null,
  createdAt: "2026-10-18T10:00:00Z",
  updatedAt: "2026-10-18T10:00:00Z",
};

describe("createOauthServer", () => {
  it("registers a public client without a secret", async () => {
    const { call, transport } = fake({ register_oauth_client: CLIENT_ROW });
    const oauth = createOauthServer({ transport });

    const registered = await oauth
      .registerClient({
        name: "CLI",
        grantTypes: ["urn:ietf:params:oauth:grant-type:device_code"],
        tokenEndpointAuthMethod: "none",
      })
      .orThrow();

    expect(registered.clientSecret).toBeNull();
    expect(registered.client.tokenEndpointAuthMethod).toBe("none");
    expect(call.mock.calls[0]?.[2]).toMatchObject({ secret_hash: null });
  });

  it("requires a redirect URI for the authorization code grant", async () => {
    const { call, transport } = fake({});
    const oauth = createOauthServer({ transport });

    expect(await oauth.registerClient({})).toMatchObject({
      ok: false,
      error: { kind: "invalid_input" },
    });
    expect(call).not.toHaveBeenCalled();
  });

  it("verifies a client secret and a registration token by hash", async () => {
    const { call, transport } = fake({
      verify_oauth_client: CLIENT_ROW,
      verify_oauth_registration_token: true,
    });

    const oauth = createOauthServer({ transport });

    expect(
      await oauth.verifyClient("bsc_client", "s3cret").orThrow(),
    ).toMatchObject({ clientId: "bsc_client" });
    expect(
      await oauth.verifyRegistrationToken("bsc_client", "tok").orThrow(),
    ).toBe(true);
    expect(call.mock.calls[0]?.[2]).toEqual({
      client_id: "bsc_client",
      secret_hash: await sha256("s3cret"),
    });
    expect(call.mock.calls[1]?.[2]).toEqual({
      client_id: "bsc_client",
      token_hash: await sha256("tok"),
    });
  });

  it("returns the new secret only when the rotation matched a client", async () => {
    const oauth = createOauthServer(fake({ rotate_oauth_client_secret: true }));

    const missing = createOauthServer(
      fake({ rotate_oauth_client_secret: false }),
    );

    expect(await oauth.rotateSecret("bsc_client").orThrow()).toBeTypeOf(
      "string",
    );
    expect(await missing.rotateSecret("bsc_client").orThrow()).toBeNull();
  });

  it("hands back the code and stores its hash with the ttl", async () => {
    const { call, transport } = fake({
      create_oauth_authorization_code: { grantId: "grant-1" },
    });

    const oauth = createOauthServer({ transport, codeSeconds: 30 });

    const issued = await oauth
      .createAuthorizationCode({
        clientId: "bsc_client",
        userId: "user-1",
        redirectUri: "https://app.example.com/cb",
        codeChallenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        codeChallengeMethod: "S256",
      })
      .orThrow();

    expect(issued.grantId).toBe("grant-1");
    expect(call.mock.calls[0]?.[2]).toMatchObject({
      code_hash: await sha256(issued.code),
      ttl: "30 seconds",
    });
  });

  it("passes RFC 8707 resources through and returns them at exchange", async () => {
    const { call, transport } = fake({
      create_oauth_authorization_code: { grantId: "grant-1" },
      redeem_oauth_authorization_code: {
        status: "ok",
        userId: "user-1",
        clientId: "bsc_client",
        grantId: "grant-1",
        scope: "openid",
        nonce: null,
        resource: ["https://api.example.com"],
      },
    });

    const oauth = createOauthServer({ transport });

    const issued = await oauth
      .createAuthorizationCode({
        clientId: "bsc_client",
        userId: "user-1",
        codeChallenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        codeChallengeMethod: "S256",
        resource: ["https://api.example.com", "https://other.example.com"],
      })
      .orThrow();

    expect(call.mock.calls[0]?.[2]).toMatchObject({
      resource: ["https://api.example.com", "https://other.example.com"],
    });

    const redeemed = await oauth
      .redeemAuthorizationCode({
        code: issued.code,
        clientId: "bsc_client",
        codeVerifier: "a".repeat(43),
        resource: ["https://api.example.com"],
      })
      .orThrow();

    expect(redeemed?.resource).toEqual(["https://api.example.com"]);
    expect(call.mock.calls[1]?.[2]).toMatchObject({
      resource: ["https://api.example.com"],
    });
  });

  it("registers a client under a chosen id", async () => {
    const { call, transport } = fake({ register_oauth_client: CLIENT_ROW });
    const oauth = createOauthServer({ transport });

    await oauth
      .registerClient(
        {
          name: "CLI",
          grantTypes: ["urn:ietf:params:oauth:grant-type:device_code"],
          tokenEndpointAuthMethod: "none",
        },
        { clientId: "acme-cli" },
      )
      .orThrow();

    expect(call.mock.calls[0]?.[2]).toMatchObject({ client_id: "acme-cli" });
  });

  it("returns null for a replayed or mismatched code", async () => {
    const oauth = createOauthServer(
      fake({ redeem_oauth_authorization_code: { status: "replayed" } }),
    );

    expect(
      await oauth
        .redeemAuthorizationCode({
          code: "code",
          clientId: "bsc_client",
          codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        })
        .orThrow(),
    ).toBeNull();
  });

  it("maps an approved device code to its authorization", async () => {
    const oauth = createOauthServer(
      fake({
        poll_oauth_device_code: {
          status: "ok",
          userId: "user-1",
          clientId: "bsc_client",
          grantId: "grant-1",
          scope: "contacts:read",
        },
      }),
    );

    expect(
      await oauth.pollDeviceCode("device", "bsc_client").orThrow(),
    ).toEqual({
      status: "ok",
      authorization: {
        userId: "user-1",
        clientId: "bsc_client",
        grantId: "grant-1",
        scope: "contacts:read",
        nonce: null,
        resource: [],
      },
    });
  });

  it("revokes a token until it expires and plugs into accessTokenResolver", async () => {
    const { call, transport } = fake({
      revoke_oauth_token: true,
      is_oauth_token_revoked: true,
    });

    const oauth = createOauthServer({ transport });
    const expiresAt = Temporal.Instant.from("2026-10-18T11:00:00Z");

    expect(
      await oauth
        .revokeToken("jti-1", expiresAt, { grantId: "grant-1" })
        .orThrow(),
    ).toBe(true);
    expect(call.mock.calls[0]?.[2]).toEqual({
      jti: "jti-1",
      expires_at: "2026-10-18T11:00:00Z",
      grant_id: "grant-1",
    });

    accessTokenResolver({
      jwks: { keys: [] },
      issuer: "https://auth.example.com",
      audience: "https://api.example.com",
      revocation: oauth,
    });
    expect(await oauth.isRevoked("jti-1", undefined).orThrow()).toBe(true);
    expect(call.mock.calls[1]?.[2]).toEqual({ jti: "jti-1", grant_id: null });
  });

  it("reads, updates and deletes a client", async () => {
    const { call, transport } = fake({
      oauth_client: CLIENT_ROW,
      update_oauth_client: null,
      delete_oauth_client: true,
    });

    const oauth = createOauthServer({ transport });

    expect(await oauth.readClient("bsc_client").orThrow()).toMatchObject({
      name: "CLI",
    });
    expect(
      await oauth.updateClient("bsc_client", { name: "New" }).orThrow(),
    ).toBeNull();
    expect(await oauth.deleteClient("bsc_client").orThrow()).toBe(true);
    expect(
      await oauth.updateClient("bsc_client", { redirectUris: ["not a url"] }),
    ).toMatchObject({
      ok: false,
      error: { hint: "OAUTH_REDIRECT_URI_INVALID" },
    });
    expect(call).toHaveBeenCalledTimes(3);
  });

  it("checks a public client without hashing", async () => {
    const { call, transport } = fake({ verify_oauth_client: null });
    const oauth = createOauthServer({ transport });

    expect(await oauth.verifyClient("bsc_client", null).orThrow()).toBeNull();
    expect(call.mock.calls[0]?.[2]).toEqual({
      client_id: "bsc_client",
      secret_hash: null,
    });
  });

  it("refuses a challenge that is not a SHA-256 digest", async () => {
    const oauth = createOauthServer(fake({}));

    expect(
      await oauth.createAuthorizationCode({
        clientId: "bsc_client",
        userId: "user-1",
        codeChallenge: "short",
        codeChallengeMethod: "S256",
      }),
    ).toMatchObject({ ok: false, error: { hint: "OAUTH_PKCE_INVALID" } });
  });

  it("looks up and decides a device request by its user code", async () => {
    const { call, transport } = fake({
      oauth_device_request: {
        clientId: "bsc_client",
        scope: null,
        expiresAt: "2026-10-18T10:10:00Z",
      },
      decide_oauth_device_code: true,
    });

    const oauth = createOauthServer({ transport });
    const none = createOauthServer(fake({ oauth_device_request: null }));

    expect(await oauth.deviceRequest("bdfg-hjkl").orThrow()).toMatchObject({
      clientId: "bsc_client",
      scope: "",
    });
    expect(await none.deviceRequest("BDFGHJKL").orThrow()).toBeNull();
    expect(await oauth.denyDeviceCode("bdfghjkl", "user-1").orThrow()).toBe(
      true,
    );
    expect(call.mock.calls[1]?.[2]).toEqual({
      user_code: "BDFGHJKL",
      user_id: "user-1",
      approve: false,
    });
  });

  it("maps invalid_grant from a device poll", async () => {
    const oauth = createOauthServer(
      fake({ poll_oauth_device_code: { status: "invalid_grant" } }),
    );

    expect(
      await oauth.pollDeviceCode("device", "bsc_client").orThrow(),
    ).toEqual({ status: "invalid_grant" });
  });

  it("lists and revokes grants and purges expired rows", async () => {
    const { call, transport } = fake({
      list_oauth_grants: [
        {
          id: "grant-1",
          userId: "user-1",
          clientId: "bsc_client",
          clientName: "CLI",
          scopes: ["contacts:read"],
          createdAt: "2026-10-18T10:00:00Z",
          updatedAt: "2026-10-18T10:00:00Z",
          revokedAt: null,
        },
      ],
      revoke_oauth_grant: true,
      purge_oauth_server: 4,
    });

    const oauth = createOauthServer({ transport });

    expect(
      await oauth.listGrants("user-1", { includeRevoked: true }).orThrow(),
    ).toMatchObject([{ id: "grant-1", clientName: "CLI", revokedAt: null }]);
    expect(call.mock.calls[0]?.[2]).toEqual({
      user_id: "user-1",
      include_revoked: true,
    });
    expect(await oauth.revokeGrant("grant-1").orThrow()).toBe(true);
    expect(await oauth.purge().orThrow()).toBe(4);
  });
});
