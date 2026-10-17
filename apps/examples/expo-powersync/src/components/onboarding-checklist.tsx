// #region recipe:onboarding-checklist
import { useOnboarding } from "better-supabase/blocks/onboarding/react";
import { tenantOf, useAuth } from "better-supabase/react";
import { ActivityIndicator, Text, View } from "react-native";

import { API_SCHEMA } from "../lib/blocks";
import { gettingStarted } from "../lib/onboarding";

/** The organization's getting-started checklist; hidden once every step is done. */
export function OnboardingChecklist() {
  const organizationId = tenantOf(useAuth()) ?? null;
  const { progress } = useOnboarding(gettingStarted, {
    organizationId,
    schema: API_SCHEMA,
  });
  if (!organizationId) {
    return null;
  }
  if (progress === undefined) {
    return <ActivityIndicator />;
  }
  if (progress.done) {
    return null;
  }
  return (
    <View style={{ gap: 8, padding: 16, borderWidth: 1, borderRadius: 12 }}>
      <Text style={{ fontSize: 17, fontWeight: "600" }}>Get started</Text>
      <Text style={{ color: "#737373" }}>
        {progress.completed} of {progress.total} steps done
      </Text>
      <View style={{ height: 6, borderRadius: 3, backgroundColor: "#e5e5e5" }}>
        <View
          style={{
            height: 6,
            borderRadius: 3,
            backgroundColor: "#111",
            width: `${(progress.completed / progress.total) * 100}%`,
          }}
        />
      </View>
      {progress.steps.map((step) => (
        <Text
          key={step.id}
          style={
            step.completed
              ? { color: "#737373", textDecorationLine: "line-through" }
              : undefined
          }
        >
          {step.completed ? "✓" : "○"} {step.title}
        </Text>
      ))}
    </View>
  );
}
// #endregion recipe:onboarding-checklist
