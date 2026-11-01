import type { Money } from "../../commerce/money.ts";

import { base64ToText, toBase64 } from "../../core/base64.ts";
import { isRecord } from "../../core/guards.ts";

/** The x402 protocol version these helpers speak. */
export const X402_VERSION = 2;

/** The x402 v2 transport headers. */
export const X402_HEADERS = {
  required: "PAYMENT-REQUIRED",
  signature: "PAYMENT-SIGNATURE",
  response: "PAYMENT-RESPONSE",
} as const;

/** One way to pay for a resource (a `PaymentRequirements` of x402 v2). */
export interface X402Requirement {
  readonly scheme: string;
  /** A CAIP-2 chain id such as `eip155:8453`. */
  readonly network: string;
  /** The amount in the asset's atomic units, as text. */
  readonly amount: string;
  /** The token contract address, or the asset's identifier on the network. */
  readonly asset: string;
  readonly payTo: string;
  readonly maxTimeoutSeconds: number;
  readonly extra?: Readonly<Record<string, unknown>>;
}

export interface X402ResourceInfo {
  readonly url: string;
  readonly description?: string;
  readonly mimeType?: string;
}

/** The `PAYMENT-REQUIRED` header, decoded. */
export interface X402PaymentRequired {
  readonly x402Version: number;
  readonly error?: string;
  readonly resource: X402ResourceInfo;
  readonly accepts: readonly X402Requirement[];
  readonly extensions?: Readonly<Record<string, unknown>>;
}

/** The `PAYMENT-SIGNATURE` header, decoded. */
export interface X402PaymentPayload {
  readonly x402Version: number;
  readonly resource?: X402ResourceInfo;
  /** The requirement the client chose from `accepts`. */
  readonly accepted: X402Requirement;
  /** The scheme's signed authorization; opaque here. */
  readonly payload: Readonly<Record<string, unknown>>;
  readonly extensions?: Readonly<Record<string, unknown>>;
}

/** What a facilitator says about a payment it verified. */
export interface X402Verification {
  readonly isValid: boolean;
  readonly invalidReason?: string;
  readonly payer?: string;
}

/** What a facilitator says about a payment it settled. */
export interface X402Settlement {
  readonly success: boolean;
  readonly errorReason?: string;
  readonly payer?: string;
  readonly transaction?: string;
  readonly network?: string;
}

/**
 * Verifies and settles payments, structurally: an x402 facilitator over
 * `fetch`, a self-hosted verifier or a test double. No client library ships
 * with better-supabase.
 */
export interface X402Facilitator {
  verify(
    payment: X402PaymentPayload,
    requirement: X402Requirement,
  ): Promise<X402Verification>;
  settle(
    payment: X402PaymentPayload,
    requirement: X402Requirement,
  ): Promise<X402Settlement>;
}

export interface X402RequirementOptions {
  /**
   * The price in the asset's atomic units: the `Money` minor units must be the
   * asset's smallest unit (6 decimals for USDC).
   */
  readonly price: Money;
  readonly network: string;
  readonly asset: string;
  readonly payTo: string;
  /** Default `exact`. */
  readonly scheme?: string;
  /** Default 60. */
  readonly maxTimeoutSeconds?: number;
  readonly extra?: Readonly<Record<string, unknown>>;
}

/** One `accepts` entry for a price as `Money`. */
export function x402Requirement(
  options: X402RequirementOptions,
): X402Requirement {
  if (options.price.amount <= 0n) {
    throw new RangeError("An x402 price is greater than zero");
  }

  return {
    scheme: options.scheme ?? "exact",
    network: options.network,
    amount: options.price.amount.toString(),
    asset: options.asset,
    payTo: options.payTo,
    maxTimeoutSeconds: options.maxTimeoutSeconds ?? 60,
    ...(options.extra === undefined ? {} : { extra: options.extra }),
  };
}

export interface PaymentRequiredOptions {
  readonly resource: X402ResourceInfo;
  readonly accepts: readonly X402Requirement[];
  /** Why the request is refused, such as `PAYMENT-SIGNATURE header is required`. */
  readonly error?: string;
  readonly extensions?: Readonly<Record<string, unknown>>;
}

/** The base64 JSON of a header value. */
export function encodeX402Header(value: unknown): string {
  return toBase64(JSON.stringify(value));
}

/** A header value's JSON, or `undefined` when it is not base64 JSON. */
export function decodeX402Header(value: string): unknown {
  try {
    return JSON.parse(base64ToText(value));
  } catch {
    return undefined;
  }
}

/**
 * The `402 Payment Required` response of a paid route: the requirements in the
 * `PAYMENT-REQUIRED` header, and the same JSON as the body.
 */
export function paymentRequired(options: PaymentRequiredOptions): Response {
  if (options.accepts.length === 0) {
    throw new RangeError("A payment required response lists what it accepts");
  }

  const body: X402PaymentRequired = {
    x402Version: X402_VERSION,
    resource: options.resource,
    accepts: options.accepts,
    ...(options.error === undefined ? {} : { error: options.error }),
    ...(options.extensions === undefined
      ? {}
      : { extensions: options.extensions }),
  };

  return Response.json(body, {
    status: 402,
    headers: {
      "content-type": "application/json",
      [X402_HEADERS.required]: encodeX402Header(body),
    },
  });
}

const text = (value: unknown): value is string => typeof value === "string";

function requirementOf(value: unknown): X402Requirement | undefined {
  if (
    !isRecord(value) ||
    !text(value["scheme"]) ||
    !text(value["network"]) ||
    !text(value["amount"]) ||
    !text(value["asset"]) ||
    !text(value["payTo"])
  ) {
    return undefined;
  }

  return {
    scheme: value["scheme"],
    network: value["network"],
    amount: value["amount"],
    asset: value["asset"],
    payTo: value["payTo"],
    maxTimeoutSeconds:
      typeof value["maxTimeoutSeconds"] === "number"
        ? value["maxTimeoutSeconds"]
        : 60,
    ...(isRecord(value["extra"]) ? { extra: value["extra"] } : {}),
  };
}

/** The payment in a `PAYMENT-SIGNATURE` value; `undefined` when malformed. */
export function parsePaymentSignature(
  value: string,
): X402PaymentPayload | undefined {
  const decoded = decodeX402Header(value);

  if (
    !isRecord(decoded) ||
    decoded["x402Version"] !== X402_VERSION ||
    !isRecord(decoded["payload"])
  ) {
    return undefined;
  }

  const accepted = requirementOf(decoded["accepted"]);

  return accepted === undefined
    ? undefined
    : {
        x402Version: X402_VERSION,
        accepted,
        payload: decoded["payload"],
        ...(isRecord(decoded["extensions"])
          ? { extensions: decoded["extensions"] }
          : {}),
      };
}

/** The entry of `accepts` the payment chose, matched on every money field. */
export function matchRequirement(
  accepts: readonly X402Requirement[],
  accepted: X402Requirement,
): X402Requirement | undefined {
  return accepts.find(
    (item) =>
      item.scheme === accepted.scheme &&
      item.network === accepted.network &&
      item.amount === accepted.amount &&
      item.asset === accepted.asset &&
      item.payTo === accepted.payTo,
  );
}

export interface WithPaymentOptions {
  readonly resource: X402ResourceInfo;
  readonly accepts: readonly X402Requirement[];
  readonly facilitator: X402Facilitator;
  /** Receives the verified payment before the handler runs. */
  readonly onVerified?: (
    payment: X402PaymentPayload,
    verification: X402Verification,
  ) => void | Promise<void>;
}

/**
 * Wraps a Request handler so it answers `402` until a request carries a valid
 * `PAYMENT-SIGNATURE`. A paid request is verified, handled, then settled; the
 * settlement goes in the `PAYMENT-RESPONSE` header. A handler response of 400
 * or more is returned without settling, so a failed call costs nothing.
 */
export function withPayment(
  handler: (request: Request) => Response | Promise<Response>,
  options: WithPaymentOptions,
): (request: Request) => Promise<Response> {
  const refuse = (error: string): Response =>
    paymentRequired({
      resource: options.resource,
      accepts: options.accepts,
      error,
    });

  return async (request) => {
    const header = request.headers.get(X402_HEADERS.signature);

    if (header === null) {
      return refuse("PAYMENT-SIGNATURE header is required");
    }

    const payment = parsePaymentSignature(header);

    if (payment === undefined) {
      return refuse("PAYMENT-SIGNATURE is not a valid x402 v2 payment");
    }

    const requirement = matchRequirement(options.accepts, payment.accepted);

    if (requirement === undefined) {
      return refuse("The payment does not match an accepted requirement");
    }

    const verification = await options.facilitator.verify(payment, requirement);

    if (!verification.isValid) {
      return refuse(verification.invalidReason ?? "The payment is invalid");
    }

    await options.onVerified?.(payment, verification);

    const response = await handler(request);

    if (response.status >= 400) {
      return response;
    }

    const settlement = await options.facilitator.settle(payment, requirement);

    if (!settlement.success) {
      return refuse(settlement.errorReason ?? "The payment did not settle");
    }

    const headers = new Headers(response.headers);
    headers.set(X402_HEADERS.response, encodeX402Header(settlement));

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  };
}
