import type { Money } from "../../commerce/money.ts";
import type { Payment } from "../../commerce/payments.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type {
  AsyncResult as AsyncResultType,
  Result,
} from "../../core/result.ts";
import type {
  AGENT_MANDATE_TYPES as MandateTypes,
  CHECKOUT_PROTOCOLS as Protocols,
  CHECKOUT_SESSION_STATUSES as Statuses,
} from "../../sql/modules/agent-checkout-values.ts";
import type { Orders } from "../orders/orders.ts";
import type { BlockOptions } from "../shared.ts";
import type { SigningKeyOwner, SigningKeys } from "../signing-keys/index.ts";

import { money } from "../../commerce/money.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { JwsError, verifyCompact } from "../../core/jws.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  AGENT_MANDATE_STATUSES,
  AGENT_MANDATE_TYPES,
  CHECKOUT_PROTOCOLS,
  CHECKOUT_SESSION_STATUSES,
} from "../../sql/modules/agent-checkout-values.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  sha256Hex,
  textOf,
} from "../shared.ts";

/** The protocol a checkout session speaks: ACP or UCP. */
export type CheckoutProtocol = (typeof Protocols)[number];

/** Where a checkout session stands. */
export type CheckoutSessionStatus = (typeof Statuses)[number];

/** `open` is the autonomous (intent) mandate, `closed` binds one checkout. */
export type AgentMandateKind = "open" | "closed";

/** The AP2 v0.2 `vct` of a mandate type. */
export type AgentMandateType = (typeof MandateTypes)[number];

export type AgentMandateStatus = (typeof AGENT_MANDATE_STATUSES)[number];

/** A checkout session: protocol state over an orders cart. */
export interface CheckoutSession {
  readonly id: string;
  readonly organizationId: string;
  readonly cartId: string;
  readonly protocol: CheckoutProtocol;
  readonly status: CheckoutSessionStatus;
  /** The buyer details the agent supplied (name, email, addresses). */
  readonly buyer?: Readonly<Record<string, unknown>>;
  /** The order the session completed with. */
  readonly orderId?: string;
  readonly expiresAt?: Temporal.Instant;
  /** An `open` or `ready` session past `expiresAt`. */
  readonly expired: boolean;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** What `createSession` resolves to. */
export interface CreatedCheckoutSession extends CheckoutSession {
  /** The idempotency key had made this session before. */
  readonly replayed: boolean;
}

export interface CreateCheckoutSessionInput {
  readonly cartId: string;
  readonly protocol: CheckoutProtocol;
  /** The agent's `Idempotency-Key`; the same key and cart return one session. */
  readonly idempotencyKey: string;
  readonly expiresAt?: Temporal.Instant;
}

export interface UpdateCheckoutSessionInput {
  readonly buyer?: Readonly<Record<string, unknown>> | null;
  /** `ready` says the details are complete; `canceled` ends the session. */
  readonly status?: "open" | "ready" | "canceled";
  readonly expiresAt?: Temporal.Instant | null;
}

export interface CheckoutSessionListOptions {
  readonly status?: CheckoutSessionStatus;
  readonly protocol?: CheckoutProtocol;
  readonly cartId?: string;
  readonly limit?: number;
  readonly offset?: number;
}

/** A stored AP2 mandate. */
export interface AgentMandate {
  readonly id: string;
  readonly organizationId: string;
  readonly sessionId?: string;
  readonly vct: AgentMandateType;
  readonly status: AgentMandateStatus;
  /** The compact signed credential as presented. */
  readonly credential: string;
  readonly credentialHash: string;
  readonly issuerKid?: string;
  readonly subject?: string;
  readonly expiresAt: Temporal.Instant;
  /** An `active` mandate past `expiresAt`. */
  readonly expired: boolean;
  readonly consumedAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
}

export interface AgentMandateListOptions {
  readonly sessionId?: string;
  readonly status?: AgentMandateStatus;
  readonly vct?: AgentMandateType;
  readonly limit?: number;
  readonly offset?: number;
}

/** The claims of a mandate whose signature and shape verified. */
export interface VerifiedMandate {
  readonly kind: AgentMandateKind;
  readonly vct: AgentMandateType;
  /** The user the mandate acts for (`sub`). */
  readonly subject: string;
  readonly issuerKid?: string;
  /** `exp`, in epoch seconds. */
  readonly expiresAtSeconds: number;
  /** An open mandate's most one checkout may total. */
  readonly maxTotal?: Money;
  /** A closed mandate's binding to one session and priced total. */
  readonly sessionId?: string;
  readonly checkoutHash?: string;
  readonly claims: Readonly<Record<string, unknown>>;
}

export type SignMandateInput =
  | {
      readonly kind: "open";
      readonly subject: string;
      /** The most one checkout under this mandate may total. */
      readonly maxTotal: Money;
      readonly expiresAt: Temporal.Instant;
    }
  | {
      readonly kind: "closed";
      readonly subject: string;
      /** The session whose cart, at today's price, the mandate binds. */
      readonly sessionId: string;
      readonly expiresAt: Temporal.Instant;
    };

export interface CompleteCheckoutSessionInput {
  /** The compact mandate the agent presents. */
  readonly mandate?: string;
  /** Passed to `orders.checkout`. */
  readonly checkout?: Parameters<Orders["checkout"]>[1];
}

/** What `completeSession` resolves to. */
export interface CompletedCheckoutSession {
  readonly session: CheckoutSession;
  /** The payment to confirm; null when the session had completed before. */
  readonly payment: Payment | null;
  readonly mandate?: AgentMandate;
}

export interface AgentCheckout {
  /** Starts a session over a cart; needs `agent-checkout.write`. */
  createSession(
    input: CreateCheckoutSessionInput,
  ): AsyncResultType<CreatedCheckoutSession>;
  /** Sets the buyer details or status of an open session; needs `write`. */
  updateSession(
    sessionId: string,
    input: UpdateCheckoutSessionInput,
  ): AsyncResultType<CheckoutSession>;
  getSession(sessionId: string): AsyncResultType<CheckoutSession>;
  listSessions(
    options?: CheckoutSessionListOptions,
  ): AsyncResultType<readonly CheckoutSession[]>;
  /** The session's cart at today's price, from the orders client. */
  priceSession(
    sessionId: string,
  ): AsyncResultType<{
    readonly session: CheckoutSession;
    readonly total: Money;
  }>;
  /** Cancels an open session; needs `write`. */
  cancelSession(sessionId: string): AsyncResultType<CheckoutSession>;
  /**
   * Completes a ready session: verifies and uses the mandate, runs the orders
   * checkout (which takes the payment through the payment provider) and links
   * the order. Service only, because the orders checkout is.
   */
  completeSession(
    sessionId: string,
    input?: CompleteCheckoutSessionInput,
  ): AsyncResultType<CompletedCheckoutSession>;
  /** Signs a mandate with the signing-keys owner's active key. */
  signMandate(input: SignMandateInput): AsyncResultType<string>;
  /** Checks a mandate's signature, type and claims against the owner's JWKS. */
  verifyMandate(credential: string): AsyncResultType<VerifiedMandate>;
  /** Verifies and stores a mandate; storing it twice returns the same row. */
  storeMandate(
    credential: string,
    options?: { readonly sessionId?: string },
  ): AsyncResultType<AgentMandate>;
  getMandate(mandateId: string): AsyncResultType<AgentMandate>;
  listMandates(
    options?: AgentMandateListOptions,
  ): AsyncResultType<readonly AgentMandate[]>;
  /** Stops an active mandate; needs `agent-checkout.manage`. */
  revokeMandate(mandateId: string): AsyncResultType<boolean>;
}

/** Options for {@link createAgentCheckout}. */
export interface AgentCheckoutOptions extends BlockOptions {
  /** Prices carts and runs the checkout; its payment provider takes the money. */
  readonly orders?: Pick<Orders, "checkout" | "priceCart">;
  /** Signs and verifies mandates with the signing-keys block. */
  readonly signing?: {
    readonly keys: Pick<SigningKeys, "jwks" | "signer">;
    readonly owner: SigningKeyOwner;
  };
  /**
   * `required` refuses to complete a session without a verified mandate.
   * Default `optional`.
   */
  readonly mandates?: "optional" | "required";
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<AgentCheckout>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const MANDATE_KINDS = {
  open: "mandate.checkout.open.1",
  closed: "mandate.checkout.1",
} as const satisfies Record<AgentMandateKind, AgentMandateType>;

const refuse = (hint: string, message: string): Result<never> =>
  err(dbError("invalid_request", message, { hint }));

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const seconds = (instant: Temporal.Instant): number =>
  Math.floor(instant.epochMilliseconds / 1000);

/**
 * The hash a closed mandate binds: the cart and the total it priced at, so a
 * changed cart or price no longer matches.
 */
export function checkoutHash(cartId: string, total: Money): Promise<string> {
  return sha256Hex(`${cartId}:${total.amount.toString()}:${total.currency}`);
}

function sessionOf(value: unknown, fn: string): CheckoutSession {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    cartId: textOf(row["cartId"]),
    protocol: enumOrThrow(row["protocol"], CHECKOUT_PROTOCOLS, "protocol"),
    status: enumOrThrow(
      row["status"],
      CHECKOUT_SESSION_STATUSES,
      "session status",
    ),
    expired: row["expired"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...(isRecord(row["buyer"]) ? { buyer: row["buyer"] } : {}),
    ...optional("orderId", optionalText(row["orderId"])),
    ...optional("expiresAt", optionalInstant(row["expiresAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function mandateOf(value: unknown, fn: string): AgentMandate {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    vct: enumOrThrow(row["vct"], AGENT_MANDATE_TYPES, "mandate type"),
    status: enumOrThrow(row["status"], AGENT_MANDATE_STATUSES, "status"),
    credential: textOf(row["credential"]),
    credentialHash: textOf(row["credentialHash"]),
    expiresAt: requiredInstant(row["expiresAt"], "expiresAt"),
    expired: row["expired"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("sessionId", optionalText(row["sessionId"])),
    ...optional("issuerKid", optionalText(row["issuerKid"])),
    ...optional("subject", optionalText(row["subject"])),
    ...optional("consumedAt", optionalInstant(row["consumedAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function moneyClaim(value: unknown): Money | undefined {
  if (
    !isRecord(value) ||
    typeof value["amount"] !== "string" ||
    typeof value["currency"] !== "string" ||
    !/^\d+$/.test(value["amount"])
  ) {
    return undefined;
  }

  return money(BigInt(value["amount"]), value["currency"]);
}

/** The claims of a verified mandate token, or why they are wrong. */
function verifiedOf(
  header: Readonly<Record<string, unknown>>,
  claims: Readonly<Record<string, unknown>>,
): Result<VerifiedMandate> {
  const vct = AGENT_MANDATE_TYPES.find((item) => item === claims["vct"]);
  const subject = claims["sub"];
  const exp = claims["exp"];

  if (vct === undefined) {
    return refuse("AGENT_MANDATE_INVALID", "The mandate has an unknown vct");
  }

  if (typeof subject !== "string" || subject === "") {
    return refuse("AGENT_MANDATE_INVALID", "The mandate has no sub");
  }

  if (typeof exp !== "number") {
    return refuse("AGENT_MANDATE_INVALID", "The mandate has no exp");
  }

  if (exp * 1000 <= Date.now()) {
    return refuse("AGENT_MANDATE_EXPIRED", "The mandate expired");
  }

  const kind: AgentMandateKind = vct === MANDATE_KINDS.open ? "open" : "closed";

  const maxTotal = moneyClaim(claims["max_total"]);
  const hash = claims["checkout_hash"];
  const sessionId = claims["session_id"];

  if (kind === "open" && maxTotal === undefined) {
    return refuse(
      "AGENT_MANDATE_INVALID",
      "An open mandate carries max_total as { amount, currency }",
    );
  }

  if (
    kind === "closed" &&
    (typeof hash !== "string" || typeof sessionId !== "string")
  ) {
    return refuse(
      "AGENT_MANDATE_INVALID",
      "A closed mandate carries checkout_hash and session_id",
    );
  }

  return ok({
    kind,
    vct,
    subject,
    expiresAtSeconds: exp,
    claims,
    ...(typeof header["kid"] === "string" ? { issuerKid: header["kid"] } : {}),
    ...(maxTotal === undefined ? {} : { maxTotal }),
    ...(typeof hash === "string" ? { checkoutHash: hash } : {}),
    ...(typeof sessionId === "string" ? { sessionId } : {}),
  });
}

/**
 * Agent checkout: ACP and UCP checkout sessions over an orders cart, and AP2
 * checkout mandates signed and verified with the signing-keys block.
 */
export function createAgentCheckout(
  options: AgentCheckoutOptions,
): AgentCheckout {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);

  const needs = <T>(value: T | undefined, what: string): Result<T> =>
    value === undefined
      ? err(
          dbError(
            "invalid_request",
            `Pass \`${what}\` to createAgentCheckout`,
            { hint: "AGENT_CHECKOUT_NOT_CONFIGURED" },
          ),
        )
      : ok(value);

  const getSession: AgentCheckout["getSession"] = (sessionId) =>
    call("get_checkout_session", { session_id: sessionId }, (value) =>
      sessionOf(value, "get_checkout_session"),
    );

  const priceSession: AgentCheckout["priceSession"] = (sessionId) =>
    AsyncResult.from(async () => {
      const orders = needs(options.orders, "orders");

      if (!orders.ok) {
        return orders;
      }

      const session = await getSession(sessionId);

      if (!session.ok) {
        return session;
      }

      const cart = await orders.data.priceCart(session.data.cartId);

      if (!cart.ok) {
        return cart;
      }

      if (cart.data.problems.length > 0) {
        return refuse(
          "CHECKOUT_CART_NOT_READY",
          "The cart cannot check out yet",
        );
      }

      return ok({ session: session.data, total: cart.data.total });
    });

  const verifyMandate: AgentCheckout["verifyMandate"] = (credential) =>
    AsyncResult.from(async () => {
      const signing = needs(options.signing, "signing");

      if (!signing.ok) {
        return signing;
      }

      const jwks = await signing.data.keys.jwks(signing.data.owner);

      if (!jwks.ok) {
        return jwks;
      }

      try {
        const { header, payload } = await verifyCompact(credential, jwks.data);

        return verifiedOf(header, payload);
      } catch (error) {
        if (error instanceof JwsError) {
          return refuse("AGENT_MANDATE_INVALID", error.message);
        }

        throw error;
      }
    });

  const storeMandate: AgentCheckout["storeMandate"] = (
    credential,
    extra = {},
  ) =>
    AsyncResult.from(async () => {
      const organizationId = await tenant();

      if (!organizationId.ok) {
        return organizationId;
      }

      const verified = await verifyMandate(credential);

      if (!verified.ok) {
        return verified;
      }

      return call(
        "store_agent_mandate",
        {
          tenant: organizationId.data,
          input: {
            vct: verified.data.vct,
            credential,
            credentialHash: await sha256Hex(credential),
            issuerKid: verified.data.issuerKid,
            subject: verified.data.subject,
            expiresAt: new Date(
              verified.data.expiresAtSeconds * 1000,
            ).toISOString(),
            sessionId: extra.sessionId,
          },
        },
        (value) => mandateOf(value, "store_agent_mandate"),
      );
    });

  // The mandate must authorize this session's priced total.
  const authorize = async (
    verified: VerifiedMandate,
    session: CheckoutSession,
    total: Money,
  ): Promise<Result<undefined>> => {
    if (verified.kind === "open") {
      const max = verified.maxTotal;

      return max !== undefined &&
        max.currency === total.currency &&
        max.amount >= total.amount
        ? ok(undefined)
        : refuse(
            "AGENT_MANDATE_LIMIT",
            "The total is above what the open mandate allows",
          );
    }

    return verified.sessionId === session.id &&
      verified.checkoutHash === (await checkoutHash(session.cartId, total))
      ? ok(undefined)
      : refuse(
          "AGENT_MANDATE_MISMATCH",
          "The closed mandate does not bind this cart and total",
        );
  };

  const completeSession: AgentCheckout["completeSession"] = (
    sessionId,
    input = {},
  ) =>
    AsyncResult.from(async (): Promise<Result<CompletedCheckoutSession>> => {
      const orders = needs(options.orders, "orders");

      if (!orders.ok) {
        return orders;
      }

      const session = await getSession(sessionId);

      if (!session.ok) {
        return session;
      }

      const current = session.data;

      if (current.status === "completed") {
        return ok({ session: current, payment: null });
      }

      if (current.status === "canceled") {
        return refuse("CHECKOUT_SESSION_FINAL", "The session is canceled");
      }

      if (current.expired) {
        return refuse("CHECKOUT_SESSION_EXPIRED", "The session expired");
      }

      if (current.status !== "ready") {
        return refuse(
          "CHECKOUT_NOT_READY",
          "Set the buyer details and the status ready first",
        );
      }

      const priced = await priceSession(sessionId);

      if (!priced.ok) {
        return priced;
      }

      let stored: AgentMandate | undefined;

      if (input.mandate === undefined) {
        if (options.mandates === "required") {
          return refuse(
            "AGENT_MANDATE_REQUIRED",
            "This checkout needs an AP2 mandate",
          );
        }
      } else {
        const verified = await verifyMandate(input.mandate);

        if (!verified.ok) {
          return verified;
        }

        const allowed = await authorize(
          verified.data,
          current,
          priced.data.total,
        );

        if (!allowed.ok) {
          return allowed;
        }

        const saved = await storeMandate(input.mandate, { sessionId });

        if (!saved.ok) {
          return saved;
        }

        stored = saved.data;

        if (verified.data.kind === "closed") {
          // Used before the payment: a failed checkout burns the mandate, a
          // double spend never happens.
          const used = await call(
            "consume_agent_mandate",
            { mandate_id: saved.data.id, session_id: sessionId },
            (value) => mandateOf(value, "consume_agent_mandate"),
          );

          if (!used.ok) {
            return used;
          }

          stored = used.data;
        }
      }

      const checkout = await orders.data.checkout(
        current.cartId,
        input.checkout,
      );

      if (!checkout.ok) {
        return checkout;
      }

      const completed = await call(
        "complete_checkout_session",
        { session_id: sessionId, order_id: checkout.data.order.id },
        (value) => sessionOf(value, "complete_checkout_session"),
      );

      if (!completed.ok) {
        return completed;
      }

      return ok({
        session: completed.data,
        payment: checkout.data.payment,
        ...(stored === undefined ? {} : { mandate: stored }),
      });
    });

  const signMandate: AgentCheckout["signMandate"] = (input) =>
    AsyncResult.from(async () => {
      const signing = needs(options.signing, "signing");

      if (!signing.ok) {
        return signing;
      }

      const base = {
        vct: MANDATE_KINDS[input.kind],
        sub: input.subject,
        iat: Math.floor(Date.now() / 1000),
        exp: seconds(input.expiresAt),
        jti: crypto.randomUUID(),
      };

      let claims: Record<string, unknown>;

      if (input.kind === "open") {
        claims = {
          ...base,
          max_total: {
            amount: input.maxTotal.amount.toString(),
            currency: input.maxTotal.currency,
          },
        };
      } else {
        const priced = await priceSession(input.sessionId);

        if (!priced.ok) {
          return priced;
        }

        claims = {
          ...base,
          session_id: input.sessionId,
          checkout_hash: await checkoutHash(
            priced.data.session.cartId,
            priced.data.total,
          ),
        };
      }

      return signing.data.keys.signer(signing.data.owner).signJwt(claims);
    });

  const client: AgentCheckout = {
    createSession: (input) =>
      AsyncResult.from(async () => {
        const organizationId = await tenant();

        if (!organizationId.ok) {
          return organizationId;
        }

        const replayed = (value: unknown): boolean =>
          isRecord(value) && value["replayed"] === true;

        return call(
          "create_checkout_session",
          {
            tenant: organizationId.data,
            cart_id: input.cartId,
            protocol: input.protocol,
            idempotency_key: input.idempotencyKey,
            request_hash: await sha256Hex(`${input.protocol}:${input.cartId}`),
            expires_at: instantArg(input.expiresAt),
          },
          (value) => ({
            ...sessionOf(value, "create_checkout_session"),
            replayed: replayed(value),
          }),
        );
      }),
    updateSession: (sessionId, input) =>
      call(
        "update_checkout_session",
        {
          session_id: sessionId,
          input: definedOf({
            buyer: input.buyer,
            status: input.status,
            expiresAt:
              input.expiresAt === undefined
                ? undefined
                : (instantArg(input.expiresAt) ?? null),
          }),
        },
        (value) => sessionOf(value, "update_checkout_session"),
      ),
    getSession,
    listSessions: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_checkout_sessions",
          { tenant: organizationId, filters: definedOf(list) },
          (value) =>
            recordsOf(value, "list_checkout_sessions").map((row) =>
              sessionOf(row, "list_checkout_sessions"),
            ),
        ),
      ),
    priceSession,
    cancelSession: (sessionId) =>
      client.updateSession(sessionId, { status: "canceled" }),
    completeSession,
    signMandate,
    verifyMandate,
    storeMandate,
    getMandate: (mandateId) =>
      call("get_agent_mandate", { mandate_id: mandateId }, (value) =>
        mandateOf(value, "get_agent_mandate"),
      ),
    listMandates: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_agent_mandates",
          { tenant: organizationId, filters: definedOf(list) },
          (value) =>
            recordsOf(value, "list_agent_mandates").map((row) =>
              mandateOf(row, "list_agent_mandates"),
            ),
        ),
      ),
    revokeMandate: (mandateId) =>
      call("revoke_agent_mandate", { mandate_id: mandateId }, Boolean),
  };

  return withBlockHooks(client, options.hooks, {
    block: "agent-checkout",
    ...(options.logger === undefined ? {} : { logger: options.logger }),
  });
}
