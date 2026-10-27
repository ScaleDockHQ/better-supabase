import { call, os } from "@orpc/server";
import { describe, expect, it } from "vitest";

import type { OrpcRequestContext } from "../../src/orpc/index.ts";

import { writeSession } from "../../src/auth/session.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { createOrpc } from "../../src/orpc/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

const sessionCookie = async (): Promise<string> =>
  writeSession([], "sb-abcdefghijklmnopqrst-auth-token", {
    access_token: await signer.sign({ sub: USER }),
    refresh_token: "r-orpc",
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    token_type: "bearer",
    user: { id: USER },
  })
    .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
    .join("; ");

describe("oRPC middleware", () => {
  const bsb = createOrpc(defineSupabase(schema), {
    env,
    auth: { jwks: signer.jwks },
  });

  const whoami = (options: Parameters<typeof bsb.middleware>[0] = {}) =>
    os
      .$context<OrpcRequestContext>()
      .use(bsb.middleware({ allow: ["none", "user"], ...options }))
      .handler(({ context }) =>
        context.auth.kind === "user" ? context.auth.user.id : context.auth.kind,
      );

  it("resolves the caller from headers when the context has no request", async () => {
    const headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });

    expect(await call(whoami(), undefined, { context: { headers } })).toBe(
      USER,
    );
    expect(
      await call(whoami(), undefined, {
        context: { headers, url: "https://api.test/rpc" },
      }),
    ).toBe(USER);
  });

  it("reads the session cookie unless cookies is false", async () => {
    const request = new Request("https://api.test/rpc", {
      headers: { cookie: await sessionCookie() },
    });

    expect(await call(whoami(), undefined, { context: { request } })).toBe(
      USER,
    );
    expect(
      await call(whoami({ cookies: false }), undefined, {
        context: { request },
      }),
    ).toBe("none");
  });

  it("still accepts bearer tokens with cookies false", async () => {
    const headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });

    expect(
      await call(whoami({ cookies: false }), undefined, {
        context: { headers },
      }),
    ).toBe(USER);
  });

  it("refuses cookies false together with refresh at setup", () => {
    expect(() => bsb.middleware({ cookies: false, refresh: true })).toThrow(
      TypeError,
    );
    expect(() =>
      bsb.middleware({ cookies: false, refresh: "navigation" }),
    ).toThrow(/can't be combined with `refresh`/);
    expect(() =>
      bsb.middleware({ cookies: false, refresh: false }),
    ).not.toThrow();
  });
});
