"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { issueReceipt } from "../donations-actions";

/** Issues the numbered tax receipt of a posted gift. */
export function IssueReceiptButton({ giftId }: { giftId: string }) {
  const t = useExtracted("donations");
  const errorMessage = useErrorMessage();

  const issue = useAction(issueReceipt, {
    onSuccess: (number) => {
      toast.success(t("Receipt {number} issued", { number }));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      disabled={issue.pending}
      onClick={() => {
        void issue.run({ giftId });
      }}
    >
      {t("Issue receipt")}
    </Button>
  );
}
