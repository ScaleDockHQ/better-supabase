"use client";

import type { EntitlementClaimOptions } from "../../../auth/entitlements.ts";
import type { FeatureGateActions, FeatureGateSnapshot } from "../client.ts";

import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createFeatureGateController } from "../client.ts";

export interface UseFeatureGateOptions {
  /** The organization to check. Default the session's active one. */
  readonly organizationId?: string | null;
  /** `config.claims.features` (default `features`), or `{ claim, keys }` for short codes. */
  readonly claim?: string | EntitlementClaimOptions;
  /** The tenant claim, `config.claims.tenant` (default `tenant_id`). */
  readonly tenantClaim?: string;
}

export interface FeatureGateState
  extends FeatureGateSnapshot, FeatureGateActions {}

/**
 * Whether the active organization's plan includes `feature`, from the
 * provider session's plan-features claim; `allowed` is `undefined` while
 * the session loads. UX only: RLS enforces the feature. The same hook runs
 * in React DOM and React Native.
 *
 * ```tsx
 * const { allowed } = useFeatureGate("exports");
 * ```
 */
export function useFeatureGate(
  feature: string,
  options: UseFeatureGateOptions = {},
): FeatureGateState {
  const { auth } = useBlockEnv();
  const { organizationId, claim, tenantClaim } = options;
  const claimKey = typeof claim === "object" ? JSON.stringify(claim) : claim;
  return useController(
    () =>
      createFeatureGateController({
        auth,
        feature,
        ...(organizationId === undefined ? {} : { organizationId }),
        ...(claim === undefined ? {} : { claim }),
        ...(tenantClaim === undefined ? {} : { tenantClaim }),
      }),
    [auth, feature, organizationId, claimKey, tenantClaim],
  ).view;
}
