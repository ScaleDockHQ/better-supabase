"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { setTemplateActive } from "../document-templates-actions";

/** Takes a template out of the fallback chain, or puts it back. */
export function TemplateToggle({
  id,
  active,
}: {
  id: string;
  active: boolean;
}) {
  const t = useExtracted("documents");
  const errorMessage = useErrorMessage();

  const toggle = useAction(setTemplateActive, {
    onSuccess: (result) => {
      toast.success(
        result.active ? t("Template activated") : t("Template deactivated"),
      );
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      variant="outline"
      disabled={toggle.pending}
      onClick={() => {
        void toggle.run({ id, active: !active });
      }}
    >
      {active ? t("Deactivate") : t("Activate")}
    </Button>
  );
}
