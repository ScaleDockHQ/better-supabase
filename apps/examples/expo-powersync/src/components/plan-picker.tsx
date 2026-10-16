// #region recipe:plan-picker
import { usePlanPicker } from "better-supabase/blocks/billing/react";
import { tenantOf, useAuth } from "better-supabase/react";
import * as WebBrowser from "expo-web-browser";
import { ActivityIndicator, Pressable, Text, View } from "react-native";

import { loadPlanCatalog, startCheckout } from "../lib/billing";

const price = (cents: number) =>
  cents === 0 ? "Free" : `$${(cents / 100).toFixed(2)} per month`;

/**
 * The plans with a checkout button each. `choose` posts to the app's own
 * API route, which talks to Stripe, and opens the Checkout URL it returns
 * in the system browser.
 */
export function PlanPicker() {
  const organizationId = tenantOf(useAuth());
  const { plans, current, pending, error, choose } = usePlanPicker({
    load: () =>
      organizationId
        ? loadPlanCatalog(organizationId)
        : Promise.resolve({ plans: [], current: undefined }),
    checkout: startCheckout,
    open: async (url) => {
      await WebBrowser.openBrowserAsync(url);
    },
  });
  if (plans === undefined) return <ActivityIndicator />;
  return (
    <View style={{ gap: 8 }}>
      <Text style={{ fontSize: 17, fontWeight: "600" }}>Plans</Text>
      {plans.map((plan) => {
        const active = plan.key === current;
        return (
          <Pressable
            key={plan.key}
            accessibilityRole="button"
            accessibilityState={{
              selected: active,
              busy: pending === plan.key,
            }}
            disabled={active || pending !== undefined}
            onPress={() => void choose(plan.key)}
            style={{
              flexDirection: "row",
              gap: 8,
              padding: 12,
              borderWidth: 1,
              borderRadius: 12,
              borderColor: active ? "#111" : "#e5e5e5",
            }}
          >
            <Text style={{ flex: 1, fontWeight: "600" }}>{plan.name}</Text>
            <Text style={{ color: "#737373" }}>{price(plan.priceCents)}</Text>
            <Text>
              {active ? "Current" : pending === plan.key ? "Opening" : "Switch"}
            </Text>
          </Pressable>
        );
      })}
      {error ? <Text style={{ color: "#b91c1c" }}>{error.message}</Text> : null}
    </View>
  );
}
// #endregion recipe:plan-picker
