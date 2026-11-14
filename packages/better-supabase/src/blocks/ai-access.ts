import type { DbError } from "../core/errors.ts";

import { dbError } from "../core/errors.ts";

/**
 * Who a call of a service-role AI block (`prompts`, `ai-evals`,
 * `ai-guardrails`) acts for. These blocks bypass row-level security, so an app
 * that serves a signed-in caller passes this and the block refuses what the
 * caller may not touch. Without it the block trusts its caller, as before.
 */
export interface AiAccess {
  /**
   * The organization the caller serves. A call fails with `forbidden` when this
   * is `undefined`, and a call that names another organization (or a record of
   * one) is refused.
   */
  readonly organizationId: string | undefined;
  /** Whether the caller holds the permission the app requires. */
  readonly allowed: boolean;
  /** The permission key reported in the `forbidden` error. */
  readonly permission?: string;
}

/**
 * The error that refuses the call before it reaches the database, or
 * `undefined` when the caller may go on.
 */
export function accessDenied(
  access: AiAccess | undefined,
  tenants: readonly (string | undefined)[] = [],
): DbError | undefined {
  if (access === undefined) {
    return;
  }

  if (!access.allowed || access.organizationId === undefined) {
    return dbError("forbidden", "Not allowed to use this AI block", {
      ...(access.permission === undefined
        ? {}
        : { permission: access.permission }),
    });
  }

  return tenants.every((tenant) => tenant === access.organizationId)
    ? undefined
    : dbError("forbidden", "The call names another organization", {
        ...(access.permission === undefined
          ? {}
          : { permission: access.permission }),
      });
}
