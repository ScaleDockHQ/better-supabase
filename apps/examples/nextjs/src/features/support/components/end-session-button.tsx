"use client";

import { useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useTransition } from "react";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { endSupportSession } from "../support-actions";

/** Ends a running support session. */
export function EndSupportSessionButton({ sessionId }: { sessionId: string }) {
  const t = useExtracted("support");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const result = await endSupportSession({ sessionId });

          if (result.ok) {
            toast.success(t("Session ended"));
          } else {
            toast.error(errorMessage(result.error));
          }
        });
      }}
    >
      {t("End session")}
    </Button>
  );
}
