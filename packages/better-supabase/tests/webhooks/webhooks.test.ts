import { describe, expect, it, onTestFinished, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import {
  authHook,
  databaseChange,
  hookError,
  signWebhook,
  timingSafeEqual,
  verifySharedSecret,
  verifyWebhook,
} from "../../src/webhooks/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

// Reference vector from the Standard Webhooks test suite.
const SECRET = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw";
const ID = "msg_p5jXN8AQM9LWM0D4loKWxJek";
const TIMESTAMP = 1_614_265_330;
const BODY = '{"test": 2432232314}';
const SIGNATURE = "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=";
const now = () => Temporal.Instant.fromEpochMilliseconds(TIMESTAMP * 1000);

const headers = (signature = SIGNATURE, timestamp = String(TIMESTAMP)) => ({
  "webhook-id": ID,
  "webhook-timestamp": timestamp,
  "webhook-signature": signature,
});

describe("Standard Webhooks", () => {
  it("returns an error instead of throwing when Temporal is missing", async () => {
    vi.stubGlobal("Temporal", undefined);
    onTestFinished(() => {
      vi.unstubAllGlobals();
    });
    const result = await verifyWebhook(
      { headers: headers(), body: BODY },
      SECRET,
    );
    expect(result.error).toMatchObject({ kind: "unexpected" });
  });

  it("matches the reference signature", async () => {
    expect(
      (
        await signWebhook(SECRET, {
          id: ID,
          body: BODY,
          timestamp: Temporal.Instant.fromEpochMilliseconds(TIMESTAMP * 1000),
        })
      )["webhook-signature"],
    ).toBe(SIGNATURE);
    const verified = await verifyWebhook(
      { headers: headers(), body: BODY },
      SECRET,
      { now },
    );
    expect(verified).toEqual({
      ok: true,
      error: null,
      data: {
        id: ID,
        timestamp: Temporal.Instant.fromEpochMilliseconds(TIMESTAMP * 1000),
        payload: { test: 2_432_232_314 },
        body: BODY,
      },
    });
  });

  it("accepts Supabase-style secrets, rotation and multiple signatures", async () => {
    const other = "whsec_" + btoa("another-secret-value");
    expect(
      (
        await verifyWebhook(
          { headers: headers(`v1,bad v1a,x ${SIGNATURE}`), body: BODY },
          `v1,${SECRET}`,
          { now },
        )
      ).ok,
    ).toBe(true);
    expect(
      (
        await verifyWebhook(
          { headers: headers(), body: BODY },
          [other, SECRET],
          { now },
        )
      ).ok,
    ).toBe(true);
  });

  it("rejects tampering, stale timestamps and missing headers", async () => {
    const code = async (input: Parameters<typeof verifyWebhook>[0]) =>
      (await verifyWebhook(input, SECRET, { now })).error?.code;
    expect(await code({ headers: headers(), body: '{"test": 1}' })).toBe(
      "WEBHOOK_INVALID_SIGNATURE",
    );
    expect(
      await code({
        headers: headers(SIGNATURE, String(TIMESTAMP - 301)),
        body: BODY,
      }),
    ).toBe("WEBHOOK_TIMESTAMP_TOO_OLD");
    expect(
      await code({
        headers: headers(SIGNATURE, String(TIMESTAMP + 301)),
        body: BODY,
      }),
    ).toBe("WEBHOOK_TIMESTAMP_TOO_NEW");
    expect(await code({ headers: { "webhook-id": ID }, body: BODY })).toBe(
      "WEBHOOK_MISSING_HEADERS",
    );
    const error = (
      await verifyWebhook({ headers: headers(), body: "{}" }, SECRET, { now })
    ).error;
    expect(error).toMatchObject({ kind: "unauthorized", status: 401 });
  });

  it("compares in constant time and checks shared secrets", () => {
    expect(timingSafeEqual("abc", "abc")).toBe(true);
    expect(timingSafeEqual("abc", "abd")).toBe(false);
    expect(timingSafeEqual("abc", "abcd")).toBe(false);
    const request = new Request("http://x", {
      headers: { authorization: "Bearer s3cret" },
    });
    expect(verifySharedSecret(request, "s3cret")).toBe(true);
    expect(verifySharedSecret(request, "other")).toBe(false);
  });
});

describe("authHook", () => {
  const secret = "v1,whsec_" + btoa("hook-secret-for-tests-0123456789");

  async function call(
    handler: Parameters<typeof authHook<"custom_access_token">>[2],
    body: unknown,
    sign = secret,
  ) {
    const text = JSON.stringify(body);
    const request = new Request("http://x/hook", {
      method: "POST",
      body: text,
      headers: await signWebhook(sign, { id: "msg_1", body: text }),
    });
    return authHook("custom_access_token", secret, handler)(request);
  }

  const payload = {
    user_id: "u1",
    claims: { sub: "u1", role: "authenticated" },
    authentication_method: "password",
  };

  it("verifies, types and answers", async () => {
    const response = await call(
      ({ claims, user_id }) => ({
        claims: { ...claims, tenant_id: `org-of-${user_id}` },
      }),
      payload,
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      claims: { sub: "u1", role: "authenticated", tenant_id: "org-of-u1" },
    });
  });

  it("passes hook errors through and rejects bad signatures", async () => {
    const rejected = await call(() => hookError(403, "Not allowed"), payload);
    expect(rejected.status).toBe(403);
    expect(await rejected.json()).toEqual({
      error: { http_code: 403, message: "Not allowed" },
    });
    const forged = await call(
      () => ({ claims: {} }),
      payload,
      "whsec_" + btoa("wrong"),
    );
    expect(forged.status).toBe(401);
  });
});

describe("databaseChange", () => {
  const sb = defineSupabase(schema);

  it("maps database webhook payloads to app casing", () => {
    const payload = {
      type: "UPDATE",
      table: "customers",
      schema: "public",
      record: { id: "c1", organization_id: "o1" },
      old_record: { id: "c1", organization_id: "o0" },
    };
    const change = databaseChange(sb, "customers", payload);
    expect(change).toEqual({
      type: "UPDATE",
      table: "customers",
      record: { id: "c1", organizationId: "o1" },
      oldRecord: { id: "c1", organizationId: "o0" },
    });
    expect(change?.record?.organizationId).toBe("o1");
    expect(databaseChange(sb, "notes", payload)).toBeNull();
    expect(databaseChange(sb, "customers", { hello: "world" })).toBeNull();
  });
});
