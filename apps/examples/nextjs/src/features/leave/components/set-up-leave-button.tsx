"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { setUpLeaveTypes } from "../leave-actions";

/** Creates vacation and sick leave and grants this year's vacation allowance. */
export function SetUpLeaveButton() {
  const t = useExtracted("people");
  const errorMessage = useErrorMessage();

  const setUp = useAction(setUpLeaveTypes, {
    onSuccess: () => {
      toast.success(t("Leave types created"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      variant="outline"
      disabled={setUp.pending}
      onClick={() => {
        void setUp.run({});
      }}
    >
      {t("Set up leave types")}
    </Button>
  );
}
