"use client";

import { useAction } from "better-supabase/react";
import { SquareIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { cancelRun } from "../agents-actions";

/** Asks the running answer of a chat to stop. */
export function CancelRunButton({ chatId }: { chatId: string }) {
  const t = useExtracted("agents");
  const errorMessage = useErrorMessage();

  const cancel = useAction(cancelRun, {
    onSuccess: () => {
      toast.success(t("Stop requested"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={cancel.pending}
      onClick={() => {
        void cancel.run({ chatId });
      }}
    >
      <SquareIcon />
      {t("Stop run")}
    </Button>
  );
}
