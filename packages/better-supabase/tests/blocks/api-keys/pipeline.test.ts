import { pipeline } from "@supabase/middleware";
import { describe, expect, it } from "vitest";

import {
  createApiKeys,
  withApiKey,
} from "../../../src/blocks/api-keys/index.ts";

const ORG = "11111111-1111-4111-8111-111111111111";
const token = `bs_0123456789abcdef_${"d".repeat(43)}`;

const keyRow = {
  id: "33333333-3333-4333-8333-333333333333",
  organization_id: ORG,
  user_id: null,
  name: "CI",
  prefix: "bs",
  public_id: "0123456789abcdef",
  scopes: ["deals:read"],
  rate_limit: 60,
  expires_at: null,
  last_used_at: null,
  revoked_at: null,
  rotated_from: null,
  created_by: null,
  created_at: "2026-10-06T09:00:00Z",
};

const keysAnswering = (answer: unknown) =>
  createApiKeys({ transport: { call: () => Promise.resolve(answer) } });

const handler = (answer: unknown) =>
  pipeline(
    [withApiKey({ keys: keysAnswering(answer) })],
    async (_request, ctx) =>
      Response.json({
        kind: ctx.auth.kind,
        sub: ctx.jwtClaims?.sub,
        apiKey: (ctx.jwtClaims as { api_key?: unknown } | null)?.api_key,
        authMode: ctx.authMode,
        userClaims: ctx.userClaims,
      }),
  );

describe("withApiKey", () => {
  it("verifies the key and contributes its claims", async () => {
    const response = await handler({ status: "ok", key: keyRow })(
      new Request("https://api.test/v1/deals", {
        headers: { "x-api-key": token },
      }),
    );
    expect(await response.json()).toMatchObject({
      kind: "apiKey",
      apiKey: { organization_id: ORG, scopes: ["deals:read"] },
      authMode: "secret",
      userClaims: null,
    });
  });

  it("answers a missing, invalid or rate-limited key with Problem Details", async () => {
    const missing = await handler({ status: "ok", key: keyRow })(
      new Request("https://api.test/v1/deals"),
    );
    expect(missing.status).toBe(401);
    expect(missing.headers.get("www-authenticate")).toContain("Bearer");
    expect(await missing.json()).toMatchObject({ code: "API_KEY_REQUIRED" });
    const invalid = await handler({ status: "invalid" })(
      new Request("https://api.test/v1/deals", {
        headers: { authorization: `Bearer ${token}` },
      }),
    );
    expect(invalid.status).toBe(401);
    expect(await invalid.json()).toMatchObject({ code: "INVALID_API_KEY" });
    const limited = await handler({ status: "rate_limited", retry_after: 5 })(
      new Request("https://api.test/v1/deals", {
        headers: { "x-api-key": token },
      }),
    );
    expect(limited.status).toBe(429);
    expect(limited.headers.get("retry-after")).toBe("5");
  });
});
