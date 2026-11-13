"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { cancelCheckoutSession } from "../checkout-sessions-actions";

/** Cancels an open or ready session from the detail head. */
export function SessionActionsBar({ sessionId }: { sessionId: string }) {
  const t = useExtracted("checkoutSessions");
  const errorMessage = useErrorMessage();

  const cancel = useAction(cancelCheckoutSession, {
    onSuccess: () => {
      toast.success(t("Session canceled"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={cancel.pending}
      onClick={() => {
        void cancel.run({ sessionId });
      }}
    >
      {t("Cancel session")}
    </Button>
  );
}
