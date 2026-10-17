// #region recipe:usage-meter
import { useUsageMeter } from "better-supabase/blocks/usage/react";
import { tenantOf, useAuth } from "better-supabase/react";
import { ActivityIndicator, Text, View } from "react-native";

import { API_SCHEMA } from "../lib/blocks";

const labels = new Map([
  ["api.calls", "API calls"],
  ["customers.created", "Customers added"],
]);

/** This period's usage per meter against the plan's quota. */
export function UsageMeter() {
  const organizationId = tenantOf(useAuth()) ?? null;

  const { meters } = useUsageMeter({
    organizationId,
    meters: ["api.calls", "customers.created"],
    schema: API_SCHEMA,
  });

  if (!organizationId) {
    return null;
  }

  if (meters === undefined) {
    return <ActivityIndicator />;
  }

  return (
    <View style={{ gap: 12, padding: 16, borderWidth: 1, borderRadius: 12 }}>
      <Text style={{ fontSize: 17, fontWeight: "600" }}>Usage this period</Text>
      {meters.map((meter) => (
        <View key={meter.meter} style={{ gap: 4 }}>
          <View style={{ flexDirection: "row" }}>
            <Text style={{ flex: 1 }}>
              {labels.get(meter.meter) ?? meter.meter}
            </Text>
            <Text style={{ color: meter.exceeded ? "#b91c1c" : "#737373" }}>
              {meter.limit === undefined
                ? `${meter.used} used, no limit`
                : `${meter.used} of ${meter.limit}`}
            </Text>
          </View>
          <View
            style={{ height: 6, borderRadius: 3, backgroundColor: "#e5e5e5" }}
          >
            <View
              style={{
                height: 6,
                borderRadius: 3,
                backgroundColor: meter.exceeded ? "#b91c1c" : "#111",
                width: `${(meter.fraction ?? 0) * 100}%`,
              }}
            />
          </View>
          <Text style={{ color: "#737373", fontSize: 12 }}>
            Resets{" "}
            {meter.resetsAt.toLocaleString(undefined, { dateStyle: "medium" })}
          </Text>
        </View>
      ))}
    </View>
  );
}
// #endregion recipe:usage-meter
