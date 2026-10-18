"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { createDefaultPipeline } from "../crm-actions";

/** Creates the "Sales" pipeline with its six stages. */
export function CreatePipelineButton() {
  const t = useExtracted("crm");
  const errorMessage = useErrorMessage();

  const create = useAction(createDefaultPipeline, {
    onSuccess: () => {
      toast.success(t("Pipeline created"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      type="button"
      disabled={create.pending}
      onClick={() => {
        void create.run(undefined);
      }}
    >
      {t("Create a sales pipeline")}
    </Button>
  );
}
