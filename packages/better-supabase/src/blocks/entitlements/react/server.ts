import type { useFeatureGate as useClientFeatureGate } from "./index.ts";

export type { FeatureGateState, UseFeatureGateOptions } from "./index.ts";

/** The `react-server` build of `useFeatureGate`: call `hasEntitlement(session, organizationId, feature)` instead. */
export const useFeatureGate: typeof useClientFeatureGate = () => {
  throw new Error(
    "better-supabase: useFeatureGate() runs in Client Components only. In Server Components call `hasEntitlement(session, organizationId, feature)` instead.",
  );
};
