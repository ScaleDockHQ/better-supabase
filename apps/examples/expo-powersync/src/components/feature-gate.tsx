// #region recipe:feature-gate
import type { ReactNode } from "react";

import { useFeatureGate } from "better-supabase/blocks/entitlements/react";
import { ActivityIndicator, Text, View } from "react-native";

/**
 * Renders `children` only when the active organization's plan includes
 * `feature`, read from the session's `features` claim. UX only: RLS checks
 * the feature too.
 */
export function FeatureGate({
  feature,
  children,
}: {
  readonly feature: string;
  readonly children: ReactNode;
}) {
  const { allowed } = useFeatureGate(feature);

  if (allowed === undefined) {
    return <ActivityIndicator />;
  }

  if (allowed) {
    return children;
  }

  return (
    <View style={{ padding: 12, borderWidth: 1, borderRadius: 12 }}>
      <Text style={{ fontWeight: "600" }}>Not in your plan</Text>
      <Text style={{ color: "#737373" }}>
        Upgrade to a plan with {feature} to use this.
      </Text>
    </View>
  );
}
// #endregion recipe:feature-gate
