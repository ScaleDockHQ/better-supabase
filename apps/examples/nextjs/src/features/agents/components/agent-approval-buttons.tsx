"use client";

import { useExtracted } from "next-intl";

import { ActionButton } from "@/features/sales/components/action-button";

import { decideApprovals } from "../agents-actions";

/** Approves or denies one pending tool call of an agent's chat. */
export function AgentApprovalButtons({
  chatId,
  approvalId,
}: {
  chatId: string;
  approvalId: string;
}) {
  const t = useExtracted("agents");
  const decisions = [{ chatId, approvalId }];

  return (
    <div className="flex gap-2">
      <ActionButton
        action={decideApprovals}
        input={{ decisions, approved: true }}
        label={t("Approve")}
        successMessage={t("Approved")}
        variant="default"
      />
      <ActionButton
        action={decideApprovals}
        input={{ decisions, approved: false }}
        label={t("Deny")}
        successMessage={t("Denied")}
      />
    </div>
  );
}
