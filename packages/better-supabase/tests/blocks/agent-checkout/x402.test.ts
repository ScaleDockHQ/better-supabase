import { describe, expect, it, vi } from "vitest";

import type {
  X402Facilitator,
  X402PaymentPayload,
} from "../../../src/blocks/agent-checkout/x402.ts";

import {
  X402_HEADERS,
  X402_VERSION,
  decodeX402Header,
  encodeX402Header,
  matchRequirement,
  parsePaymentSignature,
  paymentRequired,
  withPayment,
  x402Requirement,
} from "../../../src/blocks/agent-checkout/x402.ts";
import { money } from "../../../src/commerce/money.ts";

const base = { network: "eip155:8453", asset: "0xusdc", payTo: "0xmerchant" };

const requirement = x402Requirement({ ...base, price: money(1000n, "USD") });
const resource = { url: "https://shop.test/api" };

function signed(accepted: unknown, extra: Record<string, unknown> = {}) {
  return encodeX402Header({
    x402Version: X402_VERSION,
    accepted,
    payload: { signature: "0x1" },
    ...extra,
  });
}

function request(header?: string): Request {
  return new Request("https://shop.test/api", {
    headers: header === undefined ? {} : { [X402_HEADERS.signature]: header },
  });
}

function facilitator(
  overrides: Partial<X402Facilitator> = {},
): X402Facilitator {
  return {
    verify: () => Promise.resolve({ isValid: true, payer: "0xpayer" }),
    settle: () => Promise.resolve({ success: true, transaction: "0xtx" }),
    ...overrides,
  };
}

describe("x402Requirement", () => {
  it("defaults the scheme and timeout and keeps extra", () => {
    expect(requirement).toMatchObject({
      scheme: "exact",
      amount: "1000",
      maxTimeoutSeconds: 60,
    });
    expect(requirement).not.toHaveProperty("extra");

    expect(
      x402Requirement({
        ...base,
        price: money(5n, "USD"),
        scheme: "upto",
        maxTimeoutSeconds: 5,
        extra: { name: "USDC" },
      }),
    ).toMatchObject({
      scheme: "upto",
      maxTimeoutSeconds: 5,
      extra: { name: "USDC" },
    });
  });

  it("refuses a price of zero", () => {
    expect(() => x402Requirement({ ...base, price: money(0n, "USD") })).toThrow(
      RangeError,
    );
  });
});

describe("headers", () => {
  it("round-trips and rejects non base64 json", () => {
    expect(decodeX402Header(encodeX402Header({ a: 1 }))).toEqual({ a: 1 });
    expect(decodeX402Header("%%%not json")).toBeUndefined();
  });

  it("builds a 402 with optional error and extensions", async () => {
    const plain = paymentRequired({ resource, accepts: [requirement] });
    const body = (await plain.json()) as Record<string, unknown>;

    expect(plain.status).toBe(402);
    expect(body).not.toHaveProperty("error");
    expect(body).not.toHaveProperty("extensions");
    expect(plain.headers.get(X402_HEADERS.required)).not.toBeNull();

    const full = paymentRequired({
      resource,
      accepts: [requirement],
      error: "pay",
      extensions: { x: 1 },
    });

    expect(await full.json()).toMatchObject({
      error: "pay",
      extensions: { x: 1 },
    });
  });

  it("needs at least one accepted requirement", () => {
    expect(() => paymentRequired({ resource, accepts: [] })).toThrow(
      RangeError,
    );
  });
});

describe("parsePaymentSignature", () => {
  it("parses a payment with extra and extensions", () => {
    const parsed = parsePaymentSignature(
      signed({ ...requirement, extra: { a: 1 } }, { extensions: { e: 1 } }),
    );

    expect(parsed?.accepted.extra).toEqual({ a: 1 });
    expect(parsed?.extensions).toEqual({ e: 1 });
  });

  it("defaults the timeout and omits extensions", () => {
    const { maxTimeoutSeconds: _drop, ...rest } = requirement;
    const parsed = parsePaymentSignature(signed(rest));

    expect(parsed?.accepted.maxTimeoutSeconds).toBe(60);
    expect(parsed).not.toHaveProperty("extensions");
    expect(parsed?.accepted).not.toHaveProperty("extra");
  });

  it("rejects malformed payments", () => {
    expect(parsePaymentSignature("garbage!")).toBeUndefined();
    expect(parsePaymentSignature(encodeX402Header([]))).toBeUndefined();
    expect(
      parsePaymentSignature(
        encodeX402Header({
          x402Version: 1,
          accepted: requirement,
          payload: {},
        }),
      ),
    ).toBeUndefined();
    expect(
      parsePaymentSignature(
        encodeX402Header({ x402Version: 2, accepted: requirement }),
      ),
    ).toBeUndefined();

    for (const key of ["scheme", "network", "amount", "asset", "payTo"]) {
      expect(
        parsePaymentSignature(signed({ ...requirement, [key]: 1 })),
      ).toBeUndefined();
    }

    expect(parsePaymentSignature(signed("nope"))).toBeUndefined();
  });
});

describe("matchRequirement", () => {
  it("matches on every money field", () => {
    expect(matchRequirement([requirement], { ...requirement })).toBe(
      requirement,
    );

    for (const key of ["scheme", "network", "amount", "asset", "payTo"]) {
      expect(
        matchRequirement([requirement], { ...requirement, [key]: "other" }),
      ).toBeUndefined();
    }
  });
});

describe("withPayment", () => {
  const accepts = [requirement];

  async function run(
    header: string | undefined,
    fac: X402Facilitator,
    handler: (r: Request) => Response = () => new Response("ok"),
    onVerified?: (p: X402PaymentPayload) => void,
  ): Promise<Response> {
    return withPayment(handler, {
      resource,
      accepts,
      facilitator: fac,
      ...(onVerified === undefined ? {} : { onVerified }),
    })(request(header));
  }

  const errorOf = async (response: Response): Promise<unknown> =>
    ((await response.json()) as { error: string }).error;

  it("refuses a missing, malformed or unmatched payment", async () => {
    expect(await errorOf(await run(undefined, facilitator()))).toMatch(
      /required/u,
    );
    expect(await errorOf(await run("bad", facilitator()))).toMatch(/valid/u);
    expect(
      await errorOf(
        await run(signed({ ...requirement, amount: "1" }), facilitator()),
      ),
    ).toMatch(/does not match/u);
  });

  it("refuses an invalid payment with and without a reason", async () => {
    const header = signed(requirement);

    expect(
      await errorOf(
        await run(
          header,
          facilitator({
            verify: () =>
              Promise.resolve({ isValid: false, invalidReason: "expired" }),
          }),
        ),
      ),
    ).toBe("expired");
    expect(
      await errorOf(
        await run(
          header,
          facilitator({ verify: () => Promise.resolve({ isValid: false }) }),
        ),
      ),
    ).toBe("The payment is invalid");
  });

  it("settles a paid call and sets the response header", async () => {
    const onVerified = vi.fn();

    const response = await run(
      signed(requirement),
      facilitator(),
      () => new Response("ok", { status: 201 }),
      onVerified,
    );

    expect(response.status).toBe(201);
    expect(onVerified).toHaveBeenCalledOnce();
    expect(
      decodeX402Header(response.headers.get(X402_HEADERS.response) ?? ""),
    ).toMatchObject({ success: true });
    expect(await run(signed(requirement), facilitator())).toBeInstanceOf(
      Response,
    );
  });

  it("does not settle when the handler fails", async () => {
    const settle = vi.fn();

    const response = await run(
      signed(requirement),
      facilitator({ settle }),
      () => new Response("no", { status: 500 }),
    );

    expect(response.status).toBe(500);
    expect(settle).not.toHaveBeenCalled();
  });

  it("refuses when settlement fails", async () => {
    const header = signed(requirement);

    expect(
      await errorOf(
        await run(
          header,
          facilitator({
            settle: () =>
              Promise.resolve({ success: false, errorReason: "broke" }),
          }),
        ),
      ),
    ).toBe("broke");
    expect(
      await errorOf(
        await run(
          header,
          facilitator({ settle: () => Promise.resolve({ success: false }) }),
        ),
      ),
    ).toBe("The payment did not settle");
  });
});
