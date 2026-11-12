"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { LeaseRow } from "../lease-row";

export function useLeaseStatusLabel(): (status: string) => string {
  const t = useExtracted("leases");

  return (status) => {
    switch (status) {
      case "draft": {
        return t("Draft");
      }

      case "active": {
        return t("Active");
      }

      case "ended": {
        return t("Ended");
      }

      case "terminated": {
        return t("Terminated");
      }

      default: {
        return status;
      }
    }
  };
}

export function LeaseStatusBadge({ status }: { status: LeaseRow["status"] }) {
  const label = useLeaseStatusLabel();

  switch (status) {
    case "draft": {
      return <Badge variant="secondary">{label(status)}</Badge>;
    }

    case "active": {
      return <Badge variant="success-light">{label(status)}</Badge>;
    }

    case "ended": {
      return <Badge variant="info-light">{label(status)}</Badge>;
    }

    case "terminated": {
      return <Badge variant="destructive-light">{label(status)}</Badge>;
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}
