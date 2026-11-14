"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { SendIcon, XIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { PendingInvitation } from "@/features/organization/organization-queries";

import { Button } from "@/components/ui/button";
import {
  resendInvitation,
  revokeInvitation,
} from "@/features/organization/organization-actions";
import { RoleBadge } from "@/features/user/components/role-badge";
import { toast } from "@/lib/toast";
import { cn } from "@/lib/utils";

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

  const resend = useAction(resendInvitation, {
    onSuccess: () => {
      toast.success(t("Invitation sent again"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const resending = (id: string) =>
    resend.pendingInputs.some((input) => input.invitationId === id);

  const revoking = (id: string) =>
    revoke.pendingInputs.some((input) => input.invitationId === id);

  if (invitations.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
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
          <span className="hidden text-xs text-muted-foreground sm:inline">
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
            disabled={resending(invitation.id) || revoking(invitation.id)}
            aria-label={t("Resend invitation to {email}", {
              email: invitation.email,
            })}
            onClick={() => {
              void resend.run({ invitationId: invitation.id });
            }}
          >
            <SendIcon />
          </Button>
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
