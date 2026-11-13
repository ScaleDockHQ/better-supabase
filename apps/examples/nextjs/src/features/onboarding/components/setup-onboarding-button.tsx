"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { setUpOnboardingProgram } from "../onboarding-actions";

/** Creates the new hire program. */
export function SetUpOnboardingButton() {
  const t = useExtracted("people");
  const errorMessage = useErrorMessage();

  const setUp = useAction(setUpOnboardingProgram, {
    onSuccess: () => {
      toast.success(t("New hire program created"));
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
      {t("Set up the new hire program")}
    </Button>
  );
}
