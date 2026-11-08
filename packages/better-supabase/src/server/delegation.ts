import type {
  DelegationPermissions,
  TicketSubject,
} from "../core/contracts/authorization-hooks.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { Result } from "../core/result.ts";

import { delegatedClaims } from "../auth/delegation.ts";
import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";

/**
 * The permission keys the provider's `delegation.permissions` hook grants a
 * delegated context, `undefined` for a context that is not delegated or without
 * the hook. A throw or an answer that is not a list of strings grants nothing.
 */
export async function delegationCap(
  context: RequestContext,
  userId: string,
  permissions: DelegationPermissions | undefined,
): Promise<readonly string[] | undefined> {
  if (permissions === undefined) {
    return undefined;
  }

  const delegated = delegatedClaims(context.claims ?? {});

  if (!delegated.ok || delegated.delegation === undefined) {
    return undefined;
  }

  const { client_id, scope, authorization_details } = delegated.delegation;

  try {
    const keys: unknown = await permissions({
      userId,
      ...(context.tenant === undefined ? {} : { tenant: context.tenant }),
      ...(client_id === undefined ? {} : { clientId: client_id }),
      scopes: scope === undefined ? [] : scope.split(" "),
      ...(authorization_details === undefined
        ? {}
        : { authorizationDetails: authorization_details }),
    });

    return Array.isArray(keys) &&
      keys.every((key): key is string => typeof key === "string")
      ? keys
      : [];
  } catch {
    return [];
  }
}

/**
 * The context `forContext` runs as: `context` itself, or for a context with a
 * ticket, the context `resolve` returns for it. A ticket without a resolver, a
 * `null` answer and a throw are `forbidden`; none of them fall back to the
 * recorded actor.
 */
export async function ticketSubject(
  context: RequestContext,
  resolve: TicketSubject | undefined,
): Promise<Result<RequestContext>> {
  const ticket = context["ticket"];

  if (ticket === undefined) {
    return ok(context);
  }

  if (typeof ticket !== "string" || ticket === "") {
    return err(dbError("forbidden", "forContext got an invalid ticket"));
  }

  if (resolve === undefined) {
    return err(
      dbError(
        "forbidden",
        "forContext got a ticket but no ticket resolver: pass { ticket } or authorization.tickets.subject",
      ),
    );
  }

  let resolved: unknown;

  try {
    resolved = await resolve(ticket);
  } catch {
    resolved = null;
  }

  if (typeof resolved !== "object" || resolved === null) {
    return err(dbError("forbidden", "The ticket resolver refused the ticket"));
  }

  // SAFETY: TicketSubject returns a RequestContext or null; null and non-objects were refused above.
  return ok(resolved as RequestContext);
}
