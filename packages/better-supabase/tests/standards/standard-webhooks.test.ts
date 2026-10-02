import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import {
  signWebhook,
  timingSafeEqual,
  verifyWebhook,
} from "../../src/webhooks/index.ts";

// Reference vector from the Standard Webhooks specification test suite.
const SECRET = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw";
const ID = "msg_p5jXN8AQM9LWM0D4loKWxJek";
const TIMESTAMP = 1_614_265_330;
const BODY = '{"test": 2432232314}';
const SIGNATURE = "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=";
const now = () => TIMESTAMP * 1000;
const headers = (signature = SIGNATURE, timestamp = String(TIMESTAMP)) => ({
  "webhook-id": ID,
  "webhook-timestamp": timestamp,
  "webhook-signature": signature,
});
const verify = (
  input: Parameters<typeof verifyWebhook>[0],
  secret: string | string[] = SECRET,
) => verifyWebhook(input, secret, { now });

describe(`Standard Webhooks ${SPEC_PINS.standardWebhooks}`, () => {
  it("signs the reference vector exactly: v1, base64 HMAC-SHA256 over id.timestamp.body", async () => {
    const signed = await signWebhook(SECRET, {
      id: ID,
      body: BODY,
      timestamp: new Date(TIMESTAMP * 1000),
    });
    expect(signed).toMatchObject(headers());
    const independent = createHmac(
      "sha256",
      Buffer.from(SECRET.slice("whsec_".length), "base64"),
    )
      .update(`${ID}.${TIMESTAMP}.${BODY}`)
      .digest("base64");
    expect(signed["webhook-signature"]).toBe(`v1,${independent}`);
  });

  it("webhook-timestamp is integer seconds since the epoch", async () => {
    const signed = await signWebhook(SECRET, { id: "msg_1", body: "{}" });
    expect(signed["webhook-timestamp"]).toMatch(/^\d{10}$/);
  });

  it("verifies the reference vector and returns the parsed payload", async () => {
    const result = await verify({ headers: headers(), body: BODY });
    expect(result).toMatchObject({
      ok: true,
      data: { id: ID, payload: { test: 2_432_232_314 } },
    });
  });

  it("accepts any matching signature in a space-delimited list and ignores unknown versions", async () => {
    expect(
      (
        await verify({
          headers: headers(`v1a,AAAA v1,bm9wZQ== ${SIGNATURE}`),
          body: BODY,
        })
      ).ok,
    ).toBe(true);
    expect((await verify({ headers: headers("v2,abc"), body: BODY })).ok).toBe(
      false,
    );
  });

  it("supports key rotation with several secrets", async () => {
    const other = "whsec_" + btoa("a-different-secret-value");
    expect(
      (await verify({ headers: headers(), body: BODY }, [other, SECRET])).ok,
    ).toBe(true);
    expect((await verify({ headers: headers(), body: BODY }, [other])).ok).toBe(
      false,
    );
  });

  it("rejects a timestamp outside the tolerance window (replay protection)", async () => {
    const at = async (offset: number) =>
      (
        await verify({
          headers: headers(SIGNATURE, String(TIMESTAMP + offset)),
          body: BODY,
        })
      ).error?.code;
    expect(await at(-301)).toBe("WEBHOOK_TIMESTAMP_TOO_OLD");
    expect(await at(301)).toBe("WEBHOOK_TIMESTAMP_TOO_NEW");
    expect(await at(Number.NaN)).toBeDefined();
  });

  it("rejects a tampered body, id or missing headers with 401", async () => {
    const tampered = await verify({ headers: headers(), body: '{"test": 1}' });
    expect(tampered.error).toMatchObject({
      kind: "unauthorized",
      status: 401,
      code: "WEBHOOK_INVALID_SIGNATURE",
    });
    expect(
      (
        await verify({
          headers: { ...headers(), "webhook-id": "msg_other" },
          body: BODY,
        })
      ).ok,
    ).toBe(false);
    expect(
      (await verify({ headers: { "webhook-id": ID }, body: BODY })).error?.code,
    ).toBe("WEBHOOK_MISSING_HEADERS");
  });

  it("reads headers from a Headers object case-insensitively", async () => {
    const result = await verify({
      headers: new Headers({
        "Webhook-Id": ID,
        "Webhook-Timestamp": String(TIMESTAMP),
        "Webhook-Signature": SIGNATURE,
      }),
      body: BODY,
    });
    expect(result.ok).toBe(true);
  });

  it("compares signatures in constant time with respect to content", () => {
    expect(timingSafeEqual(SIGNATURE, SIGNATURE)).toBe(true);
    expect(timingSafeEqual(SIGNATURE, SIGNATURE.replace("g0h", "g0i"))).toBe(
      false,
    );
    expect(timingSafeEqual(SIGNATURE, `${SIGNATURE}x`)).toBe(false);
  });
});
