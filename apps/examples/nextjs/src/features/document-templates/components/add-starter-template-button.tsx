"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { addStarterTemplate } from "../document-templates-actions";

/** Creates a plain invoice template. */
export function AddStarterTemplateButton() {
  const t = useExtracted("documents");
  const errorMessage = useErrorMessage();

  const add = useAction(addStarterTemplate, {
    onSuccess: () => {
      toast.success(t("Template added"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      variant="outline"
      disabled={add.pending}
      onClick={() => {
        void add.run({});
      }}
    >
      {t("Add a starter invoice template")}
    </Button>
  );
}
