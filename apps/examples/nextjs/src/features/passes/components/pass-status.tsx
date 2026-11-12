"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { PassRow } from "../pass-row";

export function usePassStatusLabel(): (status: string) => string {
  const t = useExtracted("passes");

  return (status) => {
    switch (status) {
      case "active": {
        return t("Active");
      }

      case "revoked": {
        return t("Revoked");
      }

      default: {
        return status;
      }
    }
  };
}

export function PassStatusBadge({ status }: { status: PassRow["status"] }) {
  const label = usePassStatusLabel();

  switch (status) {
    case "active": {
      return <Badge variant="success-light">{label(status)}</Badge>;
    }

    case "revoked": {
      return <Badge variant="destructive-light">{label(status)}</Badge>;
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}
