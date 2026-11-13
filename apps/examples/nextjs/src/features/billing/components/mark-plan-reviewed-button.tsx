"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

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
