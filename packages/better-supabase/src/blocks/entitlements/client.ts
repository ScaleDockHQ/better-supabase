import type { EntitlementClaimOptions } from "../../auth/entitlements.ts";
import type { AuthPort, Controller } from "../controller.ts";

import { hasEntitlement } from "../../auth/entitlements.ts";
import { tenantOf } from "../../auth/tenant.ts";
import { defineController } from "../controller.ts";

export interface FeatureGateControllerOptions {
  readonly auth: AuthPort;
  /** The plan feature, such as `exports`: a key of `entitlements.source.plans`. */
  readonly feature: string;
  /** The organization to check. Default the session's active one, from the tenant claim. */
  readonly organizationId?: string | null;
  /** `config.claims.features` (default `features`), or `{ claim, keys }` for short codes. */
  readonly claim?: string | EntitlementClaimOptions;
  /** The tenant claim, `config.claims.tenant` (default `tenant_id`). */
  readonly tenantClaim?: string;
}

export interface FeatureGateSnapshot {
  /** `undefined` while the session loads; false when signed out or outside an organization. */
  readonly allowed: boolean | undefined;
  /** The organization the check ran for. */
  readonly organizationId: string | undefined;
}

export interface FeatureGateActions {
  /** Checks the session again, such as after a refresh the gate did not hear of. */
  readonly recheck: () => void;
}

export type FeatureGateController = Controller<
  FeatureGateSnapshot,
  FeatureGateActions
>;

/**
 * Whether the active organization's plan includes `feature`, from the
 * session's plan-features claim. It updates when the session does, so a
 * session refresh after checkout opens the gate. UX only: enforce the
 * feature in RLS with `better_supabase.has_entitlement()`.
 */
export function createFeatureGateController(
  options: FeatureGateControllerOptions,
): FeatureGateController {
  const read = (): FeatureGateSnapshot => {
    const session = options.auth.current();
    if (session.status === "loading")
      return { allowed: undefined, organizationId: undefined };
    const organizationId =
      options.organizationId ?? tenantOf(session, options.tenantClaim);
    return {
      allowed:
        organizationId === undefined
          ? false
          : hasEntitlement(
              session,
              organizationId,
              options.feature,
              options.claim,
            ),
      organizationId,
    };
  };
  return defineController<FeatureGateSnapshot, FeatureGateActions>(
    read(),
    (state) => {
      const recheck = (): void => {
        state.set(read());
      };
      return {
        actions: { recheck },
        start: () => {
          recheck();
          return options.auth.subscribe(recheck);
        },
      };
    },
  );
}
