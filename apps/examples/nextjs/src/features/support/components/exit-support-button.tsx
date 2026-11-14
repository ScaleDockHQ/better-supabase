"use client";

import { useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useTransition } from "react";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { exitSupportSession } from "../support-actions";

/** Leaves the support session; the end is recorded in the audit log. */
export function ExitSupportButton() {
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
          const result = await exitSupportSession();

          if (!result.ok) {
            toast.error(errorMessage(result.error));
          }
        });
      }}
    >
      {t("Exit session")}
    </Button>
  );
}
