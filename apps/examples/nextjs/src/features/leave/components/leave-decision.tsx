"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { cancelLeave, decideLeave } from "../leave-actions";

/** Approve, reject and cancel for one request; each shows only to who may. */
export function LeaveDecision({
  requestId,
  approvalId,
  canDecide,
  canCancel,
}: {
  requestId: string;
  approvalId: string | null;
  canDecide: boolean;
  canCancel: boolean;
}) {
  const t = useExtracted("people");
  const errorMessage = useErrorMessage();

  const approve = useAction(decideLeave, {
    onSuccess: () => {
      toast.success(t("Leave approved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const reject = useAction(decideLeave, {
    onSuccess: () => {
      toast.success(t("Leave rejected"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const cancel = useAction(cancelLeave, {
    onSuccess: () => {
      toast.success(t("Leave cancelled"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <>
      {canDecide && approvalId ? (
        <>
          <Button
            disabled={approve.pending}
            onClick={() => void approve.run({ approvalId, approved: true })}
          >
            {t("Approve")}
          </Button>
          <Button
            variant="outline"
            disabled={reject.pending}
            onClick={() => void reject.run({ approvalId, approved: false })}
          >
            {t("Reject")}
          </Button>
        </>
      ) : null}
      {canCancel ? (
        <Button
          variant="outline"
          disabled={cancel.pending}
          onClick={() => void cancel.run({ requestId })}
        >
          {t("Cancel request")}
        </Button>
      ) : null}
    </>
  );
}
