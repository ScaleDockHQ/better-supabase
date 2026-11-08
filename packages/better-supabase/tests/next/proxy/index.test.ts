import { NextRequest } from "next/server.js";
import { describe, expect, it, vi } from "vitest";

import { writeSession } from "../../../src/auth/session.ts";
import { createSupabase } from "../../../src/core/define.ts";
import { createProxy } from "../../../src/next/proxy/index.ts";
import { createTestSigner } from "../../../src/testing/jwt.ts";
import { schema } from "../../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const USER = "11111111-1111-4111-8111-111111111111";

const signer = await createTestSigner();
const auth = vi.fn<typeof fetch>();

const proxy = createProxy(createSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks, fetch: auth },
  prefetchJwks: false,
  protect: (state) =>
    state.kind === "user"
      ? undefined
      : Response.redirect("https://app.test/sign-in", 307),
});

async function cookieExpiringIn(seconds: number): Promise<string> {
  const token = await signer.sign({ sub: USER, expiresIn: seconds });

  return writeSession([], NAME, {
    access_token: token,
    refresh_token: "r-entry",
    expires_at: Math.floor(Date.now() / 1000) + seconds,
  })
    .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
    .join("; ");
}

const page = (cookie: string) =>
  new NextRequest("https://app.test/dashboard", { headers: { cookie } });

describe("createProxy", () => {
  it("redirects a signed-out visitor from the cookie alone", async () => {
    const response = await proxy(page(""));

    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe("https://app.test/sign-in");
    expect(auth).not.toHaveBeenCalled();
  });

  it("lets a valid session through without calling Auth", async () => {
    const response = await proxy(page(await cookieExpiringIn(3600)));

    expect(response.status).toBe(200);
    expect(auth).not.toHaveBeenCalled();
  });

  it("refreshes an expiring session and sets the new cookie", async () => {
    auth.mockImplementation(async () =>
      Response.json({
        access_token: await signer.sign({ sub: USER }),
        refresh_token: "r-next",
        expires_in: 3600,
      }),
    );

    const response = await proxy(page(await cookieExpiringIn(20)));

    expect(auth).toHaveBeenCalledOnce();
    expect(response.headers.getSetCookie().join("\n")).toContain(NAME);
  });
});
