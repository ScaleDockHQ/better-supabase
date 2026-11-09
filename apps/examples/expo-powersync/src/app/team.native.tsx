import { FlashList } from "@shopify/flash-list";
import { Stack } from "expo-router";
import { View } from "react-native";

import { ApiKeysTable } from "../components/api-keys-table";
import { AuditLogTable } from "../components/audit-log-table";
import { InviteDialog } from "../components/invite-dialog";
import { MembersTable } from "../components/members-table";
import { RevokeAdmin } from "../components/revoke-admin";

/**
 * IOS and Android: the members, invitations, API keys and audit log recipes,
 * with the same hooks as the Next.js example, and a role revoke whose effect
 * the revoked user's device picks up without signing in again.
 */
const sections = ["members", "revoke", "invite", "keys", "audit"] as const;

type Section = (typeof sections)[number];

function TeamSection({ item }: { readonly item: Section }) {
  switch (item) {
    case "members": {
      return <MembersTable />;
    }

    case "revoke": {
      return <RevokeAdmin />;
    }

    case "invite": {
      return <InviteDialog />;
    }

    case "keys": {
      return <ApiKeysTable />;
    }

    case "audit": {
      return <AuditLogTable />;
    }

    default: {
      const unexpected: never = item;

      throw new Error(unexpected);
    }
  }
}

export default function TeamScreen() {
  return (
    <>
      <Stack.Screen options={{ title: "Team" }} />
      <FlashList
        data={sections}
        keyExtractor={(item) => item}
        renderItem={TeamSection}
        contentContainerStyle={{ padding: 16 }}
        ItemSeparatorComponent={Separator}
      />
    </>
  );
}

function Separator() {
  return <View style={{ height: 24 }} />;
}
