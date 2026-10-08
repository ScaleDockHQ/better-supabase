"use client";

import { useAction } from "better-supabase/react";
import { FileTextIcon, HandCoinsIcon, RocketIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { requestApproval, startWorkflow } from "../workflows-actions";

/** Starts the sample workflows as the signed-in user. */
export function WorkflowActions() {
  const t = useExtracted("workflows");
  const errorMessage = useErrorMessage();
  const handlers = {
    onSuccess: () => {
      toast.success(t("Workflow started"));
    },
    onError: (error: Parameters<typeof errorMessage>[0]) => {
      toast.error(errorMessage(error));
    },
  };
  const start = useAction(startWorkflow, handlers);
  const approval = useAction(requestApproval, handlers);
  return (
    <>
      <Button
        variant="outline"
        disabled={start.pending}
        onClick={() => {
          void start.run({ workflow: "onboarding-drip" });
        }}
      >
        <RocketIcon />
        {t("Onboarding drip")}
      </Button>
      <Button
        variant="outline"
        disabled={start.pending}
        onClick={() => {
          void start.run({
            workflow: "document-ingestion",
            text: t(
              "Workflows survive restarts. Each step runs once. Runs show up here.",
            ),
          });
        }}
      >
        <FileTextIcon />
        {t("Ingest a document")}
      </Button>
      <Button
        disabled={approval.pending}
        onClick={() => {
          void approval.run({ amount: 120 });
        }}
      >
        <HandCoinsIcon />
        {t("Request approval")}
      </Button>
    </>
  );
}
