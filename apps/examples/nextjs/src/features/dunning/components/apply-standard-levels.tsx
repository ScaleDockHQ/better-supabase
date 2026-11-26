"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { applyStandardDunningLevels } from "../dunning-actions";

export function ApplyStandardLevels() {
  const t = useExtracted("finance");
  const errorMessage = useErrorMessage();

  const apply = useAction(applyStandardDunningLevels, {
    onSuccess: () => {
      toast.success(t("Reminder levels saved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={apply.pending}
      onClick={() => {
        void apply.run({});
      }}
    >
      {t("Use the standard levels")}
    </Button>
  );
}
