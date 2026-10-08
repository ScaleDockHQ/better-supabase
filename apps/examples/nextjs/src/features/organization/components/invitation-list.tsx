"use client";

import { useAction } from "better-supabase/react";
import { XIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { RoleBadge } from "@/features/user/components/role-badge";
import { useErrorMessage } from "@/lib/use-error-message";
import { cn } from "@/lib/utils";

import type { PendingInvitation } from "../organization-queries";

import { revokeInvitation } from "../organization-actions";

/**
 * Only the token's hash is stored, so a pending invitation's link can't be
 * shown again; revoke it and invite again for a new one.
 */
export function InvitationList({
  invitations,
}: {
  invitations: readonly PendingInvitation[];
}) {
  const t = useExtracted("organization");
  const errorMessage = useErrorMessage();
  const format = useFormatter();
  const revoke = useAction(revokeInvitation, {
    onSuccess: () => {
      toast.success(t("Invitation revoked"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });
  const revoking = (id: string) =>
    revoke.pendingInputs.some((input) => input.invitationId === id);
  if (invitations.length === 0) {
    return (
      <p className="text-muted-foreground text-sm">
        {t("No open invitations.")}
      </p>
    );
  }
  return (
    <ul className="divide-y" data-testid="invitations">
      {invitations.map((invitation) => (
        <li
          key={invitation.id}
          aria-busy={revoking(invitation.id) ? true : undefined}
          className={cn(
            "flex items-center gap-3 py-2 text-sm",
            revoking(invitation.id) && "opacity-50",
          )}
        >
          <span className="flex-1 truncate font-medium">
            {invitation.email}
          </span>
          <RoleBadge role={invitation.role} />
          <span className="text-muted-foreground hidden text-xs sm:inline">
            {t("Expires {date}", {
              date: invitation.expiresAt
                ? format.dateTime(new Date(invitation.expiresAt), {
                    dateStyle: "medium",
                  })
                : "–",
            })}
          </span>
          <Button
            variant="ghost"
            size="icon-sm"
            disabled={revoking(invitation.id)}
            aria-label={t("Revoke invitation for {email}", {
              email: invitation.email,
            })}
            onClick={() => {
              void revoke.run({ invitationId: invitation.id });
            }}
          >
            <XIcon />
          </Button>
        </li>
      ))}
    </ul>
  );
}
