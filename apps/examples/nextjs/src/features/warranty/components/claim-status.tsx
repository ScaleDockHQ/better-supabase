"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { ClaimRow } from "../claim-row";

export function useClaimStatusLabel(): (status: string) => string {
  const t = useExtracted("warranty");

  return (status) => {
    switch (status) {
      case "draft": {
        return t("Draft");
      }

      case "submitted": {
        return t("Submitted");
      }

      case "approved": {
        return t("Approved");
      }

      case "denied": {
        return t("Denied");
      }

      case "closed": {
        return t("Closed");
      }

      default: {
        return status;
      }
    }
  };
}

export function ClaimStatusBadge({ status }: { status: ClaimRow["status"] }) {
  const label = useClaimStatusLabel();

  switch (status) {
    case "draft": {
      return <Badge variant="secondary">{label(status)}</Badge>;
    }

    case "submitted": {
      return <Badge variant="warning-light">{label(status)}</Badge>;
    }

    case "approved": {
      return <Badge variant="success-light">{label(status)}</Badge>;
    }

    case "denied": {
      return <Badge variant="destructive-light">{label(status)}</Badge>;
    }

    case "closed": {
      return <Badge variant="outline">{label(status)}</Badge>;
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}
