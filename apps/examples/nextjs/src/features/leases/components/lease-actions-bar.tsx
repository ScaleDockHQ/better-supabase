"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import type { LeaseRow } from "../lease-row";

import { activateLease, terminateLease } from "../leases-actions";

/** Activate a draft or end an active lease from the detail head. */
export function LeaseActionsBar({
  leaseId,
  status,
}: {
  leaseId: string;
  status: LeaseRow["status"];
}) {
  const t = useExtracted("leases");
  const errorMessage = useErrorMessage();

  const options = {
    onSuccess: () => {
      toast.success(t("Lease updated"));
    },
    onError: (error: Parameters<typeof errorMessage>[0]) => {
      toast.error(errorMessage(error));
    },
  };

  const activate = useAction(activateLease, options);
  const terminate = useAction(terminateLease, options);

  return (
    <>
      {status === "draft" ? (
        <Button
          size="sm"
          disabled={activate.pending}
          onClick={() => {
            void activate.run({ leaseId });
          }}
        >
          {t("Activate")}
        </Button>
      ) : null}
      {status === "active" ? (
        <Button
          size="sm"
          variant="outline"
          disabled={terminate.pending}
          onClick={() => {
            void terminate.run({ leaseId });
          }}
        >
          {t("Terminate today")}
        </Button>
      ) : null}
    </>
  );
}
