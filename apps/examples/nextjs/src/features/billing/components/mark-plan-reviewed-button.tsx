"use client";

import { useExtracted } from "next-intl";
import { useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { markPlanReviewed } from "../billing-actions";

export function MarkPlanReviewedButton() {
  const t = useExtracted("billing");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();
  return (
    <Button
      variant="outline"
      size="sm"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const result = await markPlanReviewed({});
          if (result.ok) toast.success(t("Onboarding step done"));
          else toast.error(errorMessage(result.error));
        });
      }}
    >
      {t("Mark as reviewed")}
    </Button>
  );
}
