import { useLoaderData } from "expo-router";
import { Text, View } from "react-native";

import { bsb } from "../lib/supabase/server";

interface IslandCounts {
  readonly customers: number;
  readonly notes: number;
  readonly tasks: number;
}

/**
 * Web only: one `bootstrap_islands` call returns the session flag, the live
 * authorization version and the counts. The layout and page loaders of one
 * navigation share it, and `getAccess` checks against the live version, so a
 * role revoked since the token was issued is already gone here.
 */
export const loader = bsb.loader(
  async (_ctx, _params, request) => {
    const boot = await bsb.bootstrap<IslandCounts>(request, { rpc: "islands" });
    const access = await bsb.getAccess(request, { bootstrap: boot });

    return {
      counts: boot.data,
      stale: boot.stale,
      canWrite: await access.can("customers.write"),
    };
  },
  { allow: ["user"] },
);

/**
 * Web: the counts from the loader. The notifications, organizations, search and
 * onboarding screens are in the iOS and Android app.
 */
export default function ActivityScreen() {
  const { counts, stale, canWrite } = useLoaderData<typeof loader>();

  return (
    <View style={{ gap: 8, padding: 16 }}>
      <Text>
        {counts === null
          ? "Your session ended. Sign in again."
          : `${counts.customers} customers, ${counts.notes} notes, ${counts.tasks} tasks`}
      </Text>
      {stale ? (
        <Text style={{ color: "#737373" }}>
          Your permissions changed; they apply on the next refresh.
        </Text>
      ) : null}
      <Text style={{ color: "#737373" }}>
        {canWrite ? "You can edit customers." : "You can read customers."}
      </Text>
      <Text>Open the other screens in the iOS or Android app.</Text>
    </View>
  );
}
