import { Link } from "expo-router";
import { useState } from "react";
import { View } from "react-native";

import { CommandSearch } from "../components/command-search";
import { NotificationBell } from "../components/notification-bell";
import { NotificationList } from "../components/notification-list";
import { OnboardingChecklist } from "../components/onboarding-checklist";
import { OrganizationSwitcher } from "../components/organization-switcher";
import { loadOrganizations } from "../lib/organizations.native";

/** IOS and Android: the UI recipes, with the same hooks as the Next.js example. */
export default function ActivityScreen() {
  const [showList, setShowList] = useState(false);

  return (
    <View style={{ flex: 1, gap: 16, padding: 16 }}>
      <View style={{ flexDirection: "row", justifyContent: "space-between" }}>
        <CommandSearch />
        <NotificationBell
          onPress={() => {
            setShowList((current) => !current);
          }}
        />
      </View>
      <OrganizationSwitcher load={loadOrganizations} />
      <View style={{ flexDirection: "row", gap: 16 }}>
        <Link href="/billing">Plans and usage</Link>
        <Link href="/settings">Preferences</Link>
      </View>
      <OnboardingChecklist />
      {showList ? <NotificationList /> : null}
    </View>
  );
}
