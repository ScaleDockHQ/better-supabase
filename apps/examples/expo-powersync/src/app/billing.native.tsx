import { ScrollView, Text } from "react-native";

import { FeatureGate } from "../components/feature-gate";
import { PlanPicker } from "../components/plan-picker";
import { UsageMeter } from "../components/usage-meter";

/**
 * IOS and Android: plans, usage and a plan feature, with the same hooks as the
 * Next.js example.
 */
export default function BillingScreen() {
  return (
    <ScrollView contentContainerStyle={{ gap: 16, padding: 16 }}>
      <PlanPicker />
      <UsageMeter />
      <FeatureGate feature="exports">
        <Text>CSV exports are in your plan.</Text>
      </FeatureGate>
    </ScrollView>
  );
}
