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
    ).toMatchObject({ error: { code: "WEBHOOK_INVALID_SIGNATURE" } });
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

describe("Stripe Connect and thin events", () => {
  const verify = stripeInboxVerify(secret, { now });

  const deliver = async (payload: unknown) => {
    const text = JSON.stringify(payload);

    const request = new Request("https://app.test", {
      method: "POST",
      headers: {
        "stripe-signature": await signStripeWebhook(secret, text, at),
      },
    });

    return verify(request, text);
  };

  it("stores a Connect event with the connected account", async () => {
    const connect = {
      id: "evt_connect",
      type: "checkout.session.completed",
      account: "acct_connected",
      data: { object: { id: "cs_1" } },
    };

    expect(await deliver(connect)).toMatchObject({
      ok: true,
      data: { id: "evt_connect", payload: connect },
    });
  });

  it("stores a thin event notification from an event destination", async () => {
    const thin = {
      id: "evt_thin",
      object: "v2.core.event",
      type: "v2.core.account[configuration.customer].updated",
      created: "2026-10-06T12:00:00.000Z",
      livemode: false,
      context: "acct_connected",
      related_object: {
        id: "acct_1",
        type: "v2.core.account",
        url: "/v2/core/accounts/acct_1",
      },
    };

    expect(await deliver(thin)).toMatchObject({
      ok: true,
      data: { id: "evt_thin", payload: thin },
    });
  });
});

describe("Stripe replay checks through seen", () => {
  const signed = async (text = body, when = at) => ({
    headers: {
      "stripe-signature": await signStripeWebhook(secret, text, when),
    },
    body: text,
  });

  it("records the event id until the tolerance ends and refuses a replay", async () => {
    const ids = new Map<string, Temporal.Instant>();

    const seen = (id: string, until: Temporal.Instant) => {
      if (ids.has(id)) {
        return true;
      }

      ids.set(id, until);

      return false;
    };

    const input = await signed();
    expect((await verifyStripeWebhook(input, secret, { now, seen })).ok).toBe(
      true,
    );
    expect(ids.get("evt_1")?.epochMilliseconds).toBe(
      (at.epochMilliseconds / 1000 + 300) * 1000,
    );
    expect(
      (await verifyStripeWebhook(input, secret, { now, seen })).error,
    ).toMatchObject({ kind: "conflict", code: "WEBHOOK_REPLAYED" });
  });

  it("asks seen only for a verified event with an id", async () => {
    const asked: string[] = [];

    const seen = (id: string) => {
      asked.push(id);

      return false;
    };

    const forged = await signed();
    await verifyStripeWebhook(forged, "whsec_other", { now, seen });
    await verifyStripeWebhook(
      await signed(body, at.subtract({ minutes: 10 })),
      secret,
      { now, seen },
    );
    await verifyStripeWebhook(await signed("nope"), secret, { now, seen });
    expect(asked).toEqual([]);

    expect(
      await verifyStripeWebhook(await signed("[]"), secret, { now, seen }),
    ).toMatchObject({ ok: true, data: { id: "" } });
    expect(asked).toEqual([]);
  });

  it("refuses the event when seen throws", async () => {
    const result = await verifyStripeWebhook(await signed(), secret, {
      now,
      seen: () => {
        throw new Error("redis down");
      },
    });

    expect(result.error).toMatchObject({ code: "WEBHOOK_DEDUPE_FAILED" });
  });
});
