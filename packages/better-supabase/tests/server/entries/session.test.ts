import { pipeline } from "@supabase/middleware";
import { describe, expect, it, vi } from "vitest";

import { writeSession } from "../../../src/auth/session.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { serverCore } from "../../../src/server/entries/core.ts";
import { withSession } from "../../../src/server/entries/session.ts";
import { createServer } from "../../../src/server/server.ts";
import { createTestSigner } from "../../../src/testing/jwt.ts";
import { schema } from "../../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

function cookieRequest(token: string, refresh: string): Request {
  const cookie = writeSession([], NAME, {
    access_token: token,
    refresh_token: refresh,
    expires_at: Math.floor(Date.now() / 1000) + 20,
  })
    .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
    .join("; ");
  return new Request("https://app.test/", { headers: { cookie } });
}

describe("withSession onAuthOutage", () => {
  it("answers with the hook's response only when the session is lost", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () => {
      throw new TypeError("fetch failed");
    });
    const server = createServer(defineSupabase(schema), {
      env: {
        url: PROJECT_URL,
        publishableKey: "sb_publishable_test",
        jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
      },
      auth: { jwks: signer.jwks as never, fetch },
      prefetchJwks: false,
    });
    const onAuthOutage = vi.fn(
      () =>
        new Response("down", { status: 503, headers: { "retry-after": "5" } }),
    );
    const handler = vi.fn(() => Promise.resolve(new Response("ok")));
    const run = pipeline(
      [withSession(serverCore(server), { refresh: true, onAuthOutage })],
      handler,
    );

    const lost = await run(cookieRequest("opaque", "s-1"));
    expect(lost.status).toBe(503);
    expect(lost.headers.get("retry-after")).toBe("5");
    expect(handler).not.toHaveBeenCalled();

    const token = await signer.sign({ sub: USER, expiresIn: 20 });
    const kept = await run(cookieRequest(token, "s-2"));
    expect(kept.status).toBe(200);
    expect(handler).toHaveBeenCalledTimes(1);
    expect(onAuthOutage).toHaveBeenLastCalledWith(
      expect.objectContaining({ cause: "network", kept: true }),
      expect.any(Request),
    );
  });
});
