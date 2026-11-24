"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { satisfyDeadline } from "../deadlines-actions";

export function MarkDeadlineDone({ deadlineId }: { deadlineId: string }) {
  const t = useExtracted("work");
  const errorMessage = useErrorMessage();

  const satisfy = useAction(satisfyDeadline, {
    onSuccess: () => {
      toast.success(t("Deadline marked done"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={satisfy.pending}
      onClick={() => {
        void satisfy.run({ deadlineId });
      }}
    >
      {t("Mark done")}
    </Button>
  );
}
