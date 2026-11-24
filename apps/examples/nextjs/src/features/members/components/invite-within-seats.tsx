"use client";

import { useExtracted } from "next-intl";

import type { Role } from "@/lib/claims";

import { inviteWithinSeats } from "@/features/composites/composites-actions";
import { useRoleLabel } from "@/features/organization/use-role-label";
import { ActionDialog } from "@/features/sales/components/action-dialog";

/**
 * Invites a teammate through `saas.inviteWithinSeats`: the server counts the
 * members against the plan's seats before it sends the invitation.
 */
export function InviteWithinSeats({
  assignable,
}: {
  assignable: readonly Role[];
}) {
  const t = useExtracted("members");
  const roleLabel = useRoleLabel();

  return (
    <ActionDialog
      action={inviteWithinSeats}
      title={t("Invite within the seats")}
      description={t(
        "The invitation is refused when the plan has no seat left.",
      )}
      trigger={t("Invite within seats")}
      submitLabel={t("Send invitation")}
      successMessage={t("Invitation sent")}
      variant="outline"
      fields={[
        { name: "email", label: t("Email"), kind: "text", required: true },
        {
          name: "role",
          label: t("Role"),
          kind: "select",
          options: assignable.map((role) => ({
            value: role,
            label: roleLabel(role),
          })),
        },
      ]}
    />
  );
}
