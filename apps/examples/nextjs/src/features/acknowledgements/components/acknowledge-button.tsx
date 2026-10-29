"use client";

import { useAction } from "better-supabase/react";
import { CheckIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { acknowledgeRecord } from "../acknowledgements-actions";

/** Acknowledges the version of the record the member read. */
export function AcknowledgeButton({
  type,
  id,
  versionId,
  title,
}: {
  type: string;
  id: string;
  versionId: string;
  title: string;
}) {
  const t = useExtracted("acknowledgements");
  const message = useErrorMessage();

  const acknowledge = useAction(acknowledgeRecord, {
    onSuccess: () => {
      toast.success(t("Acknowledged {title}", { title }));
    },
    onError: (error) => {
      toast.error(message(error));
    },
  });

  return (
    <Button
      type="button"
      size="sm"
      variant="outline"
      disabled={acknowledge.pending}
      onClick={() => {
        void acknowledge.run({ type, id, versionId });
      }}
    >
      <CheckIcon aria-hidden />
      {t("I've read it")}
    </Button>
  );
}
