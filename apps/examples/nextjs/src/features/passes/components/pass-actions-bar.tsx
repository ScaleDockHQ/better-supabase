"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { PassRow } from "../pass-row";

import { checkInPass, revokePass } from "../passes-actions";

/** Check in and revoke on the pass detail head. */
export function PassActionsBar({
  passId,
  status,
  canManage,
  canCheckIn,
}: {
  passId: string;
  status: PassRow["status"];
  canManage: boolean;
  canCheckIn: boolean;
}) {
  const t = useExtracted("passes");
  const errorMessage = useErrorMessage();

  const checkIn = useAction(checkInPass, {
    onSuccess: (admitted) => {
      if (admitted) {
        toast.success(t("Checked in"));
      } else {
        toast.error(t("The pass was turned away"));
      }
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const revoke = useAction(revokePass, {
    onSuccess: () => {
      toast.success(t("Pass revoked"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <>
      {canCheckIn && status === "active" ? (
        <Button
          size="sm"
          disabled={checkIn.pending}
          onClick={() => {
            void checkIn.run({ passId });
          }}
        >
          {t("Check in")}
        </Button>
      ) : null}
      {canManage && status === "active" ? (
        <Button
          size="sm"
          variant="outline"
          disabled={revoke.pending}
          onClick={() => {
            void revoke.run({ passId });
          }}
        >
          {t("Revoke")}
        </Button>
      ) : null}
    </>
  );
}
