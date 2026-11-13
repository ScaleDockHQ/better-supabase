import { none, routeAuth } from "eve/channels/auth";
import { describe, expect, it, vi } from "vitest";

import { EveAuthRejection, supabaseJwtAuth } from "../../src/eve/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { writeSession } from "../fixtures/session-cookies.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const COOKIE = "sb-abcdefghijklmnopqrst-auth-token";
const USER = "11111111-1111-4111-8111-111111111111";
const ORG = "22222222-2222-4222-8222-222222222222";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const signer = await createTestSigner();

/**
 * No call may leave the process: the keys are inline and a valid token needs no
 * Auth call.
 */
const offline = vi.fn<typeof fetch>(() =>
  Promise.reject(new Error("unexpected fetch")),
);

const auth = () =>
  supabaseJwtAuth({
    env,
    jwks: { keys: [...signer.jwks.keys] },
    fetch: offline,
  });

const bearer = (token: string): Request =>
  new Request("https://app.test/eve/v1/session", {
    headers: { authorization: `Bearer ${token}` },
  });

describe("supabaseJwtAuth", () => {
  it("maps a verified access token to a principal without calling Auth", async () => {
    const token = await signer.sign({
      sub: USER,
      app_metadata: { tenant_id: ORG },
      memberships: [{ id: ORG, roles: ["admin"] }],
    });

    expect(await auth()(bearer(token))).toMatchObject({
      authenticator: "supabase",
      principalType: "user",
      principalId: USER,
      attributes: { tenantId: ORG, roles: ["admin"], isAnonymous: "false" },
    });
    expect(offline).not.toHaveBeenCalled();
  });

  it("ignores the session cookie and falls through without a bearer token", async () => {
    const token = await signer.sign({ sub: USER });

    const cookie = writeSession([], COOKIE, {
      access_token: token,
      refresh_token: "refresh",
      expires_at: Math.floor(Date.now() / 1000) + 3600,
    })
      .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
      .join("; ");

    expect(
      await auth()(new Request("https://app.test/", { headers: { cookie } })),
    ).toBeNull();
  });

  it("rejects an invalid token with an RFC 6750 challenge", async () => {
    const rejected = await auth()(bearer("not.a.token")).catch(
      (error: unknown) => error,
    );

    expect(rejected).toBeInstanceOf(EveAuthRejection);
    const { response } = rejected as EveAuthRejection;
    expect(response.status).toBe(401);
    expect(response.headers.get("www-authenticate")).toBe(
      'Bearer error="invalid_token"',
    );
  });

  it("works in eve's auth walk: an invalid token never reaches none()", async () => {
    const entries = [auth(), none()];

    const rejected = await routeAuth(bearer("not.a.token"), entries);
    expect(rejected).toBeInstanceOf(Response);
    expect((rejected as Response).status).toBe(401);

    const anonymous = await routeAuth(
      new Request("https://app.test/"),
      entries,
    );

    expect(anonymous).toMatchObject({ principalType: "anonymous" });
  });

  it("advertises the Bearer scheme when no entry accepts the request", async () => {
    const response = await routeAuth(new Request("https://app.test/"), [
      auth(),
    ]);

    expect(response).toBeInstanceOf(Response);
    expect((response as Response).headers.get("www-authenticate")).toBe(
      "Bearer",
    );
  });
});
