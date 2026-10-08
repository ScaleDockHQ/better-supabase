"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { markPlanReviewed } from "../billing-actions";

export function MarkPlanReviewedButton() {
  const t = useExtracted("billing");
  const errorMessage = useErrorMessage();
  const review = useAction(markPlanReviewed, {
    onSuccess: () => {
      toast.success(t("Onboarding step done"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });
  return (
    <Button
      variant="outline"
      size="sm"
      disabled={review.pending}
      onClick={() => {
        void review.run({});
      }}
    >
      {t("Mark as reviewed")}
    </Button>
  );
}
