"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { WorkflowIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { setUpChangeWorkflow } from "../change-requests-actions";

/** Publishes the default change lifecycle for the organization. */
export function SetUpChangeWorkflowButton() {
  const t = useExtracted("changeRequests");
  const errorMessage = useErrorMessage();

  const setUp = useAction(setUpChangeWorkflow, {
    onSuccess: () => {
      toast.success(t("Change workflow published"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      disabled={setUp.pending}
      onClick={() => {
        void setUp.run({});
      }}
    >
      <WorkflowIcon />
      {t("Set up the change workflow")}
    </Button>
  );
}
