import { describe, expect, it } from "vitest";

import type { X402Facilitator } from "../../src/blocks/agent-checkout/index.ts";

import {
  decodeX402Header,
  encodeX402Header,
  paymentRequired,
  withPayment,
  X402_HEADERS,
  X402_VERSION,
  x402Requirement,
} from "../../src/blocks/agent-checkout/index.ts";
import { money } from "../../src/commerce/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const requirement = x402Requirement({
  price: money(10_000n, "USD"),
  network: "eip155:8453",
  asset: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  payTo: "0xabc",
});

const resource = { url: "https://api.test/report" };

const signature = (accepted: unknown) =>
  encodeX402Header({
    x402Version: X402_VERSION,
    accepted,
    payload: { signature: "0x1" },
  });

const facilitator = (calls: string[], valid = true): X402Facilitator => ({
  verify: () => {
    calls.push("verify");

    return Promise.resolve({ isValid: valid, invalidReason: "bad" });
  },
  settle: () => {
    calls.push("settle");

    return Promise.resolve({ success: true, transaction: "0xtx" });
  },
});

describe("x402 v2", () => {
  it("pins the protocol version the headers carry", () => {
    expect(String(X402_VERSION)).toBe(SPEC_PINS.x402);
    expect(X402_HEADERS).toEqual({
      required: "PAYMENT-REQUIRED",
      signature: "PAYMENT-SIGNATURE",
      response: "PAYMENT-RESPONSE",
    });
  });

  it("answers 402 with the requirements in the header and the body", async () => {
    const response = paymentRequired({ resource, accepts: [requirement] });

    const header = decodeX402Header(
      response.headers.get("PAYMENT-REQUIRED") ?? "",
    );

    expect(response.status).toBe(402);
    expect(header).toEqual(await response.json());
    expect(header).toMatchObject({
      x402Version: 2,
      accepts: [{ scheme: "exact", amount: "10000", network: "eip155:8453" }],
    });
  });

  it("refuses a price that is not positive", () => {
    expect(() =>
      x402Requirement({
        price: money(0n, "USD"),
        network: "eip155:8453",
        asset: "a",
        payTo: "b",
      }),
    ).toThrow(RangeError);
  });

  it("verifies, runs the handler, then settles", async () => {
    const calls: string[] = [];

    const handler = withPayment(
      () => {
        calls.push("handler");

        return Response.json({ ok: true });
      },
      { resource, accepts: [requirement], facilitator: facilitator(calls) },
    );

    const response = await handler(
      new Request("https://api.test/report", {
        headers: { "PAYMENT-SIGNATURE": signature(requirement) },
      }),
    );

    expect(calls).toEqual(["verify", "handler", "settle"]);
    expect(response.status).toBe(200);
    expect(
      decodeX402Header(response.headers.get("PAYMENT-RESPONSE") ?? ""),
    ).toMatchObject({ success: true, transaction: "0xtx" });
  });

  it("does not settle when the handler fails", async () => {
    const calls: string[] = [];

    const handler = withPayment(() => new Response("no", { status: 500 }), {
      resource,
      accepts: [requirement],
      facilitator: facilitator(calls),
    });

    const response = await handler(
      new Request("https://api.test/report", {
        headers: { "PAYMENT-SIGNATURE": signature(requirement) },
      }),
    );

    expect(response.status).toBe(500);
    expect(calls).toEqual(["verify"]);
  });

  it("answers 402 without a payment, with an invalid one and with another price", async () => {
    const calls: string[] = [];

    const handler = withPayment(() => Response.json({}), {
      resource,
      accepts: [requirement],
      facilitator: facilitator(calls, false),
    });

    expect((await handler(new Request("https://api.test/r"))).status).toBe(402);

    const cheaper = { ...requirement, amount: "1" };

    expect(
      (
        await handler(
          new Request("https://api.test/r", {
            headers: { "PAYMENT-SIGNATURE": signature(cheaper) },
          }),
        )
      ).status,
    ).toBe(402);

    expect(calls).toEqual([]);

    expect(
      (
        await handler(
          new Request("https://api.test/r", {
            headers: { "PAYMENT-SIGNATURE": signature(requirement) },
          }),
        )
      ).status,
    ).toBe(402);

    expect(calls).toEqual(["verify"]);
  });
});
