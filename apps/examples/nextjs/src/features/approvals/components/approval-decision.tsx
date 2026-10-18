"use client";

import { useAction } from "better-supabase/react";
import { CheckIcon, XIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { decideApproval } from "../approvals-actions";

/** Approve and Reject for one request's current step. */
export function ApprovalDecision({ id, label }: { id: string; label: string }) {
  const t = useExtracted("approvals");
  const errorMessage = useErrorMessage();

  const decide = useAction(decideApproval, {
    onSuccess: (status) => {
      toast.success(
        status === "pending"
          ? t("Approved. The next step is waiting.")
          : status === "approved"
            ? t("Request approved")
            : t("Request rejected"),
      );
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <div className="flex items-center justify-end gap-2">
      <Button
        size="sm"
        variant="outline"
        disabled={decide.pending}
        aria-label={t("Reject {label}", { label })}
        onClick={() => {
          void decide.run({ id, decision: "reject" });
        }}
      >
        <XIcon />
        {t("Reject")}
      </Button>
      <Button
        size="sm"
        disabled={decide.pending}
        aria-label={t("Approve {label}", { label })}
        onClick={() => {
          void decide.run({ id, decision: "approve" });
        }}
      >
        <CheckIcon />
        {t("Approve")}
      </Button>
    </div>
  );
}
