import { FlashList } from "@shopify/flash-list";
import { Text, View } from "react-native";

import { FeatureGate } from "../components/feature-gate";
import { PlanPicker } from "../components/plan-picker";
import { UsageMeter } from "../components/usage-meter";

/**
 * IOS and Android: plans, usage and a plan feature, with the same hooks as the
 * Next.js example.
 */
const sections = ["plans", "usage", "exports"] as const;

type Section = (typeof sections)[number];

function BillingSection({ item }: { readonly item: Section }) {
  switch (item) {
    case "plans": {
      return <PlanPicker />;
    }

    case "usage": {
      return <UsageMeter />;
    }

    case "exports": {
      return (
        <FeatureGate feature="exports">
          <Text>CSV exports are in your plan.</Text>
        </FeatureGate>
      );
    }

    default: {
      const unexpected: never = item;

      throw new Error(unexpected);
    }
  }
}

export default function BillingScreen() {
  return (
    <FlashList
      data={sections}
      keyExtractor={(item) => item}
      renderItem={BillingSection}
      contentContainerStyle={{ padding: 16 }}
      ItemSeparatorComponent={Separator}
    />
  );
}

function Separator() {
  return <View style={{ height: 16 }} />;
}
