// #region recipe:invite-dialog
import { useInvitations } from "better-supabase/blocks/organizations/react";
import { tenantOf, useAuth } from "better-supabase/react";
import { useState } from "react";
import { Button, Modal, Pressable, Text, TextInput, View } from "react-native";

import { API_SCHEMA } from "../lib/blocks";

const ROLES = ["member", "admin"] as const;

/**
 * A button that opens a form to invite a teammate by email with a role, then
 * shows the token for the accept link (the example has no mailer).
 */
export function InviteDialog() {
  const [open, setOpen] = useState(false);
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<(typeof ROLES)[number]>("member");

  const { invitations, invite, inviting, sent, error, clear } = useInvitations({
    organizationId: tenantOf(useAuth()),
    schema: API_SCHEMA,
  });

  const close = () => {
    setOpen(false);
    setEmail("");
    clear();
  };

  return (
    <View style={{ gap: 4 }}>
      <Text style={{ fontSize: 17, fontWeight: "600" }}>
        Pending invitations
      </Text>
      {invitations?.map((invitation) => (
        <Text key={invitation.id}>
          {invitation.email} ({invitation.role})
        </Text>
      ))}
      <Button
        title="Invite"
        onPress={() => {
          setOpen(true);
        }}
      />
      <Modal visible={open} animationType="slide" onRequestClose={close}>
        <View style={{ flex: 1, gap: 12, padding: 24 }}>
          {sent ? (
            <>
              <Text style={{ fontSize: 17, fontWeight: "600" }}>
                Invitation created
              </Text>
              <Text>Send this token in the accept link. It works once.</Text>
              <Text selectable style={{ fontFamily: "monospace" }}>
                {sent.token}
              </Text>
            </>
          ) : (
            <>
              <Text style={{ fontSize: 17, fontWeight: "600" }}>
                Invite a teammate
              </Text>
              <TextInput
                value={email}
                onChangeText={setEmail}
                placeholder="Email"
                keyboardType="email-address"
                autoCapitalize="none"
                autoComplete="off"
                style={{ borderWidth: 1, borderRadius: 8, padding: 8 }}
              />
              <View style={{ flexDirection: "row", gap: 8 }}>
                {ROLES.map((each) => (
                  <Pressable
                    key={each}
                    accessibilityRole="radio"
                    accessibilityState={{ checked: each === role }}
                    onPress={() => {
                      setRole(each);
                    }}
                    style={{
                      borderWidth: 1,
                      borderRadius: 16,
                      paddingHorizontal: 12,
                      paddingVertical: 4,
                      backgroundColor: each === role ? "#e5e5e5" : undefined,
                    }}
                  >
                    <Text>{each}</Text>
                  </Pressable>
                ))}
              </View>
              {error ? (
                <Text style={{ color: "#b91c1c" }}>{error.message}</Text>
              ) : null}
              <Button
                title="Send invitation"
                disabled={inviting || !email.trim()}
                onPress={() =>
                  void invite({ email: email.trim().toLowerCase(), role })
                }
              />
            </>
          )}
          <Button title={sent ? "Done" : "Cancel"} onPress={close} />
        </View>
      </Modal>
    </View>
  );
}
// #endregion recipe:invite-dialog
