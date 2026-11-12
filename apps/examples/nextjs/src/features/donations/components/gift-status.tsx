"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { GiftRow } from "../gift-row";

export function useGiftStatusLabel(): (status: string) => string {
  const t = useExtracted("donations");

  return (status) => {
    switch (status) {
      case "pending": {
        return t("Pending");
      }

      case "posted": {
        return t("Posted");
      }

      case "failed": {
        return t("Failed");
      }

      case "refunded": {
        return t("Refunded");
      }

      default: {
        return status;
      }
    }
  };
}

export function GiftStatusBadge({ status }: { status: GiftRow["status"] }) {
  const label = useGiftStatusLabel();

  switch (status) {
    case "pending": {
      return <Badge variant="warning-light">{label(status)}</Badge>;
    }

    case "posted": {
      return <Badge variant="success-light">{label(status)}</Badge>;
    }

    case "failed": {
      return <Badge variant="destructive-light">{label(status)}</Badge>;
    }

    case "refunded": {
      return <Badge variant="secondary">{label(status)}</Badge>;
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}
