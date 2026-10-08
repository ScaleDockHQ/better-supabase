import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";

import {
  signStripeWebhook,
  stripeInboxVerify,
  verifyStripeWebhook,
} from "../../../src/blocks/webhooks/index.ts";

const secret = "whsec_test_secret";
const body = JSON.stringify({ id: "evt_1", type: "invoice.paid" });
const at = Temporal.Instant.from("2026-10-06T12:00:00Z");
const now = () => at;

describe("Stripe signatures", () => {
  it("signs like Stripe: HMAC-SHA256 of t.body with the secret's UTF-8 bytes", async () => {
    const header = await signStripeWebhook(secret, body, at);
    const expected = createHmac("sha256", secret)
      .update(`1791288000.${body}`)
      .digest("hex");
    expect(header).toBe(`t=1791288000,v1=${expected}`);
  });

  it("verifies a signed event and any of several secrets", async () => {
    const header = await signStripeWebhook(secret, body, at);
    const request = new Request("https://app.test/stripe", {
      method: "POST",
      headers: { "stripe-signature": `${header},v0=ignored` },
      body,
    });
    const verified = await verifyStripeWebhook(request, ["whsec_old", secret], {
      now,
    });
    expect(verified).toMatchObject({
      ok: true,
      data: { id: "evt_1", payload: { type: "invoice.paid" } },
    });
  });

  it("rejects missing, stale, forged and non-JSON input", async () => {
    const header = await signStripeWebhook(secret, body, at);
    const check = (headers: Record<string, string>, text = body, clock = now) =>
      verifyStripeWebhook({ headers, body: text }, secret, { now: clock });
    expect(await check({})).toMatchObject({
      error: { code: "WEBHOOK_MISSING_HEADERS" },
    });
    expect(await check({ "Stripe-Signature": "v1=abc" })).toMatchObject({
      error: { code: "WEBHOOK_INVALID_TIMESTAMP" },
    });
    expect(
      await check({ "stripe-signature": header }, body, () =>
        at.add({ minutes: 10 }),
      ),
    ).toMatchObject({ error: { code: "WEBHOOK_TIMESTAMP_OUT_OF_RANGE" } });
    expect(
      await check({ "stripe-signature": header }, `${body} `),
    ).toMatchObject({
      error: { code: "WEBHOOK_INVALID_SIGNATURE" },
    });
    const notJson = await signStripeWebhook(secret, "nope", at);
    expect(await check({ "stripe-signature": notJson }, "nope")).toMatchObject({
      error: { kind: "invalid_request" },
    });
    const noId = await signStripeWebhook(secret, "[]", at);
    expect(await check({ "stripe-signature": noId }, "[]")).toMatchObject({
      ok: true,
      data: { id: "" },
    });
  });

  it("adapts to createWebhookInbox's verify option", async () => {
    const verify = stripeInboxVerify(secret, { now });
    const header = await signStripeWebhook(secret, body, at);
    const request = new Request("https://app.test", {
      method: "POST",
      headers: { "stripe-signature": header },
    });
    expect(await verify(request, body)).toMatchObject({
      ok: true,
      data: { id: "evt_1" },
    });
    expect(await verify(request, "{}")).toMatchObject({ ok: false });
  });
});
