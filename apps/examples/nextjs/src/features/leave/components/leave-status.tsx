"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { LeaveRow } from "../leave-list";

export function useLeaveStatusLabel() {
  const t = useExtracted("people");

  return (status: string): string => {
    switch (status) {
      case "pending": {
        return t("Pending");
      }

      case "approved": {
        return t("Approved");
      }

      case "rejected": {
        return t("Rejected");
      }

      case "cancelled": {
        return t("Cancelled");
      }

      default: {
        return status;
      }
    }
  };
}

const VARIANTS = {
  pending: "warning-light",
  approved: "success-light",
  rejected: "destructive-light",
  cancelled: "secondary",
} as const satisfies Record<LeaveRow["status"], string>;

export function LeaveStatusBadge({ status }: { status: LeaveRow["status"] }) {
  const label = useLeaveStatusLabel();

  return <Badge variant={VARIANTS[status]}>{label(status)}</Badge>;
}
