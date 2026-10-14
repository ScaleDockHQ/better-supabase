import type { Actor, RequestContext } from "../../core/plugin.ts";
import type { JobContext } from "./types.ts";

import { DELEGATION_CLAIMS, delegatedClaims } from "../../auth/delegation.ts";
import { impersonatorClaim, impersonatorOf } from "../../auth/impersonation.ts";
import { tenantFrom, tenantPathsFor } from "../../core/claims.ts";
import { dbError } from "../../core/errors.ts";
import { err, ok, type Result } from "../../core/result.ts";

/** Marks a payload that carries a job context; pgmq stores it as the payload. */
const ENVELOPE = "$bs";

export interface WrapOptions {
  /** The opaque ticket `forContext` resolves; wins over `context.ticket`. */
  readonly ticket?: string;
}

function ticketOf(
  context: RequestContext | undefined,
  options: WrapOptions,
): Result<string | undefined> {
  const ticket = options.ticket ?? context?.["ticket"];
  if (ticket === undefined) return ok(undefined);
  if (typeof ticket === "string" && ticket !== "") return ok(ticket);
  return err(
    dbError("validation", "A job ticket is a non-empty string", {
      issues: [{ message: "Expected a non-empty string", path: ["ticket"] }],
    }),
  );
}

/**
 * The context a job records: the actor, the tenant, the ticket, and the
 * `act` chain and delegation of the token, so a job an OAuth or MCP client
 * queued runs with that client's scopes, never the user's full rights.
 * An invalid `act` chain or malformed delegation is `forbidden`.
 */
export function recordContext(
  context: RequestContext | undefined,
  options: WrapOptions = {},
): Result<JobContext | undefined> {
  const ticket = ticketOf(context, options);
  if (!ticket.ok) return ticket;
  if (!context) {
    return ok(ticket.data === undefined ? undefined : { ticket: ticket.data });
  }
  const claims = context.claims ?? {};
  const delegated = delegatedClaims(claims);
  if (!delegated.ok) {
    return err(
      dbError(
        "forbidden",
        delegated.reason === "invalid-chain"
          ? "The job context has an invalid act claim"
          : "The job context has invalid delegation claims",
      ),
    );
  }
  const tenant = tenantFrom(context, tenantPathsFor(undefined));
  const impersonator = impersonatorOf(claims);
  const recorded: JobContext = {
    ...(context.actor ? { actor: context.actor } : {}),
    ...(tenant === undefined ? {} : { tenant }),
    ...(ticket.data === undefined ? {} : { ticket: ticket.data }),
    ...delegated.delegation,
    ...(impersonator ? { act: impersonatorClaim(impersonator) } : {}),
  };
  if (
    !recorded.actor &&
    recorded.tenant === undefined &&
    recorded.ticket === undefined
  ) {
    return ok(undefined);
  }
  return ok(recorded);
}

/** Wraps a payload with the recorded context of `context`, when there is one. */
export function wrapPayload(
  payload: unknown,
  context: RequestContext | undefined,
  options: WrapOptions = {},
): Result<unknown> {
  const recorded = recordContext(context, options);
  if (!recorded.ok) return recorded;
  return ok(
    recorded.data === undefined
      ? payload
      : { [ENVELOPE]: 1, context: recorded.data, payload },
  );
}

/** `wrapPayload` that throws a `TypeError` for a context it refuses. */
export function withContext(
  payload: unknown,
  context: RequestContext | undefined,
  options: WrapOptions = {},
): unknown {
  const wrapped = wrapPayload(payload, context, options);
  if (!wrapped.ok) throw new TypeError(wrapped.error.message);
  return wrapped.data;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isActor(value: unknown): value is Actor {
  return (
    isRecord(value) &&
    typeof value["id"] === "string" &&
    (value["kind"] === "user" ||
      value["kind"] === "service" ||
      value["kind"] === "anon")
  );
}

/**
 * Splits a stored payload into the payload and its recorded context. The
 * recorded `act` and delegation claims come back as they were stored, so
 * `forContext` checks them again and refuses a malformed one.
 */
export function unwrap(stored: unknown): {
  payload: unknown;
  context: RequestContext;
} {
  if (
    !isRecord(stored) ||
    stored[ENVELOPE] !== 1 ||
    !Object.hasOwn(stored, "payload")
  ) {
    return { payload: stored, context: {} };
  }
  const recorded = isRecord(stored["context"]) ? stored["context"] : {};
  const { actor, tenant, ticket } = recorded;
  const claims = Object.fromEntries(
    DELEGATION_CLAIMS.filter(
      (key) => Object.hasOwn(recorded, key) && recorded[key] !== undefined,
    ).map((key) => [key, recorded[key]]),
  );
  return {
    payload: stored["payload"],
    context: {
      ...(isActor(actor) ? { actor } : {}),
      ...(typeof tenant === "string" && tenant.length > 0 ? { tenant } : {}),
      ...(ticket === undefined ? {} : { ticket }),
      ...(Object.keys(claims).length > 0 ? { claims } : {}),
    },
  };
}
