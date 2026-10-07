import type { Actor, RequestContext } from "../../core/plugin.ts";
import type { JobContext } from "./queue.ts";

import { impersonatorClaim, impersonatorOf } from "../../auth/impersonation.ts";
import { tenantFrom, tenantPathsFor } from "../../core/claims.ts";

/** Marks a payload that carries a job context; pgmq stores it as the payload. */
const ENVELOPE = "$bs";

/** Wraps a payload with the actor and tenant of `context`, when it has either. */
export function withContext(
  payload: unknown,
  context: RequestContext | undefined,
): unknown {
  if (!context) return payload;
  const tenant = tenantFrom(context, tenantPathsFor(undefined));
  const impersonator = context.claims
    ? impersonatorOf(context.claims)
    : undefined;
  const recorded: JobContext = {
    ...(context.actor ? { actor: context.actor } : {}),
    ...(tenant === undefined ? {} : { tenant }),
    ...(impersonator ? { act: impersonatorClaim(impersonator) } : {}),
  };
  if (!recorded.actor && recorded.tenant === undefined) return payload;
  return { [ENVELOPE]: 1, context: recorded, payload };
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

/** Splits a stored payload into the payload and its recorded context. */
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
  const { actor, tenant, act } = recorded;
  const impersonator = act === undefined ? undefined : impersonatorOf({ act });
  return {
    payload: stored["payload"],
    context: {
      ...(isActor(actor) ? { actor } : {}),
      ...(typeof tenant === "string" && tenant.length > 0 ? { tenant } : {}),
      ...(impersonator
        ? { claims: { act: impersonatorClaim(impersonator) } }
        : {}),
    },
  };
}
