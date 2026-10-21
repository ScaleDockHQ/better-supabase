import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createOAuthServer,
  sqlTransport,
} from "../../src/blocks/oauth-server/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const VERIFIER = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
const CHALLENGE = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
const REDIRECT = "https://app.example.com/callback";

describe.skipIf(!live)("oauth-server module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("redeems a PKCE code once and revokes the grant on a replay", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["oauth-server"]);
      const user = await s.user("oauth");
      await s.service();
      await s.client.query("set local role service_role");
      const oauth = createOAuthServer({ transport: sqlTransport(s.sql) });

      const { client, clientSecret, registrationAccessToken } = await oauth
        .registerClient({
          name: "Desktop",
          redirectUris: [REDIRECT],
          scope: "contacts:read",
        })
        .orThrow();

      expect(
        await oauth.verifyClient(client.clientId, clientSecret).orThrow(),
      ).toMatchObject({ clientId: client.clientId });
      expect(
        await oauth.verifyClient(client.clientId, "wrong").orThrow(),
      ).toBeNull();
      expect(
        await oauth
          .verifyRegistrationToken(client.clientId, registrationAccessToken)
          .orThrow(),
      ).toBe(true);

      const issued = await oauth
        .createAuthorizationCode({
          clientId: client.clientId,
          userId: user.id,
          redirectUri: REDIRECT,
          scope: "contacts:read",
          codeChallenge: CHALLENGE,
          codeChallengeMethod: "S256",
        })
        .orThrow();

      const redemption = {
        code: issued.code,
        clientId: client.clientId,
        redirectUri: REDIRECT,
        codeVerifier: VERIFIER,
      };

      expect(
        await oauth.redeemAuthorizationCode(redemption).orThrow(),
      ).toMatchObject({
        userId: user.id,
        grantId: issued.grantId,
        scope: "contacts:read",
      });
      expect(
        await oauth.redeemAuthorizationCode(redemption).orThrow(),
      ).toBeNull();
      expect(await oauth.isRevoked("any-jti", issued.grantId).orThrow()).toBe(
        true,
      );
    } finally {
      await s.close();
    }
  });

  it("narrows resources at exchange and refuses a wider request", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["oauth-server"]);
      const user = await s.user("oauth-resource");
      await s.service();
      await s.client.query("set local role service_role");
      const oauth = createOAuthServer({ transport: sqlTransport(s.sql) });

      const { client } = await oauth
        .registerClient({ name: "Desktop", redirectUris: [REDIRECT] })
        .orThrow();

      const request = async () =>
        oauth
          .createAuthorizationCode({
            clientId: client.clientId,
            userId: user.id,
            redirectUri: REDIRECT,
            codeChallenge: CHALLENGE,
            codeChallengeMethod: "S256",
            resource: ["https://a.example.com", "https://b.example.com"],
          })
          .orThrow();

      const base = {
        clientId: client.clientId,
        redirectUri: REDIRECT,
        codeVerifier: VERIFIER,
      };

      const narrowed = await request();

      expect(
        await oauth
          .redeemAuthorizationCode({
            ...base,
            code: narrowed.code,
            resource: ["https://a.example.com"],
          })
          .orThrow(),
      ).toMatchObject({ resource: ["https://a.example.com"] });

      const wider = await request();

      expect(
        await oauth
          .redeemAuthorizationCode({
            ...base,
            code: wider.code,
            resource: ["https://c.example.com"],
          })
          .orThrow(),
      ).toBeNull();
    } finally {
      await s.close();
    }
  });

  it("runs the device flow and checks revoked tokens", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["oauth-server"]);
      const user = await s.user("device");
      await s.service();
      await s.client.query("set local role service_role");
      const oauth = createOAuthServer({ transport: sqlTransport(s.sql) });

      const { client } = await oauth
        .registerClient({
          name: "CLI",
          grantTypes: ["urn:ietf:params:oauth:grant-type:device_code"],
          tokenEndpointAuthMethod: "none",
        })
        .orThrow();

      const device = await oauth
        .createDeviceCode(client.clientId, "contacts:read")
        .orThrow();

      expect(
        await oauth
          .pollDeviceCode(device.deviceCode, client.clientId)
          .orThrow(),
      ).toEqual({ status: "authorization_pending", interval: 5 });
      expect(
        await oauth
          .pollDeviceCode(device.deviceCode, client.clientId)
          .orThrow(),
      ).toEqual({ status: "slow_down", interval: 10 });
      expect(
        await oauth.deviceRequest(device.userCode.toLowerCase()).orThrow(),
      ).toMatchObject({ clientId: client.clientId });
      expect(
        await oauth.approveDeviceCode(device.userCode, user.id).orThrow(),
      ).toBe(true);

      await s.client.query("reset role");
      await s.client.query(
        "update better_supabase.oauth_device_codes set last_polled_at = now() - interval '1 minute'",
      );
      await s.client.query("set local role service_role");

      const approved = await oauth
        .pollDeviceCode(device.deviceCode, client.clientId)
        .orThrow();

      expect(approved).toMatchObject({
        status: "ok",
        authorization: { userId: user.id },
      });

      const grantId =
        approved.status === "ok" ? approved.authorization.grantId : "";

      expect(await oauth.isRevoked("jti-1", grantId).orThrow()).toBe(false);
      await oauth
        .revokeToken("jti-1", Temporal.Now.instant().add({ minutes: 10 }), {
          grantId,
        })
        .orThrow();
      expect(await oauth.isRevoked("jti-1", grantId).orThrow()).toBe(true);
      expect(await oauth.isRevoked("jti-2", "not-a-uuid").orThrow()).toBe(true);

      await s.asRole(user);
      expect(await s.value("better_supabase.my_oauth_grants()")).toMatchObject([
        { clientId: client.clientId, scopes: ["contacts:read"] },
      ]);
      expect(
        await s.value("better_supabase.revoke_my_oauth_grant($1)", [grantId]),
      ).toBe(true);
      expect(
        await s.hint("select * from better_supabase.oauth_clients"),
      ).not.toBe("no error");
    } finally {
      await s.close();
    }
  });
});
