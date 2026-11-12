"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { ClaimRow } from "../claim-row";

import { decideClaim, submitClaim } from "../warranty-actions";
import { DecideClaimDialog } from "./decide-claim-dialog";

/** Submit, decide or close a claim from the detail head. */
export function ClaimActionsBar({
  claimId,
  status,
  canWrite,
  canDecide,
}: {
  claimId: string;
  status: ClaimRow["status"];
  canWrite: boolean;
  canDecide: boolean;
}) {
  const t = useExtracted("warranty");
  const errorMessage = useErrorMessage();

  const options = {
    onSuccess: () => {
      toast.success(t("Claim updated"));
    },
    onError: (error: Parameters<typeof errorMessage>[0]) => {
      toast.error(errorMessage(error));
    },
  };

  const submit = useAction(submitClaim, options);
  const decide = useAction(decideClaim, options);

  return (
    <>
      {status === "draft" && canWrite ? (
        <Button
          size="sm"
          disabled={submit.pending}
          onClick={() => {
            void submit.run({ claimId });
          }}
        >
          {t("Submit")}
        </Button>
      ) : null}
      {status === "submitted" && canDecide ? (
        <>
          <DecideClaimDialog claimId={claimId} status="approved" />
          <DecideClaimDialog claimId={claimId} status="denied" />
        </>
      ) : null}
      {(status === "approved" || status === "denied") && canDecide ? (
        <Button
          size="sm"
          variant="outline"
          disabled={decide.pending}
          onClick={() => {
            void decide.run({ claimId, status: "closed" });
          }}
        >
          {t("Close")}
        </Button>
      ) : null}
    </>
  );
}
