"use client";

import { useExtracted } from "next-intl";

import { ActionButton } from "@/features/sales/components/action-button";

import { decideApproval } from "../agents-actions";

/** Approves or denies one pending tool call of an agent's chat. */
export function AgentApprovalButtons({ approvalId }: { approvalId: string }) {
  const t = useExtracted("agents");

  return (
    <div className="flex gap-2">
      <ActionButton
        action={decideApproval}
        input={{ approvalId, approved: true }}
        label={t("Approve")}
        successMessage={t("Approved")}
        variant="default"
      />
      <ActionButton
        action={decideApproval}
        input={{ approvalId, approved: false }}
        label={t("Deny")}
        successMessage={t("Denied")}
      />
    </div>
  );
}
