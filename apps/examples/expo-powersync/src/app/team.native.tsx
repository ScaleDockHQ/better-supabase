import { Stack } from "expo-router";
import { ScrollView } from "react-native";

import { ApiKeysTable } from "../components/api-keys-table";
import { AuditLogTable } from "../components/audit-log-table";
import { InviteDialog } from "../components/invite-dialog";
import { MembersTable } from "../components/members-table";

/** iOS and Android: the members, invitations, API keys and audit log recipes, with the same hooks as the Next.js example. */
export default function TeamScreen() {
  return (
    <ScrollView contentContainerStyle={{ gap: 24, padding: 16 }}>
      <Stack.Screen options={{ title: "Team" }} />
      <MembersTable />
      <InviteDialog />
      <ApiKeysTable />
      <AuditLogTable />
    </ScrollView>
  );
}
