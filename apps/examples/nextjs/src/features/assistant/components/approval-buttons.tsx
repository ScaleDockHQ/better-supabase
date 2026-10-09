"use client";

import { useAction } from "better-supabase/react";
import { CheckIcon, XIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { decideApproval } from "../durable/durable-actions";

/** Approves or denies one tool call from the activity console. */
export function ApprovalButtons({
  chatId,
  approvalId,
}: {
  chatId: string;
  approvalId: string;
}) {
  const t = useExtracted("assistant");
  const errorMessage = useErrorMessage();
  const decide = useAction(decideApproval, {
    onSuccess: (approved) => {
      toast.success(approved ? t("Approved") : t("Denied"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });
  return (
    <div className="flex gap-2">
      <Button
        size="sm"
        disabled={decide.pending}
        onClick={() => {
          void decide.run({ chatId, approvalId, approved: true });
        }}
      >
        <CheckIcon />
        {t("Approve")}
      </Button>
      <Button
        size="sm"
        variant="outline"
        disabled={decide.pending}
        onClick={() => {
          void decide.run({ chatId, approvalId, approved: false });
        }}
      >
        <XIcon />
        {t("Deny")}
      </Button>
    </div>
  );
}
