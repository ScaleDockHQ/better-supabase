"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { SessionRow } from "../session-row";

export function useSessionStatusLabel(): (status: string) => string {
  const t = useExtracted("checkoutSessions");

  return (status) => {
    switch (status) {
      case "open": {
        return t("Open");
      }

      case "ready": {
        return t("Ready");
      }

      case "completed": {
        return t("Completed");
      }

      case "canceled": {
        return t("Canceled");
      }

      default: {
        return status;
      }
    }
  };
}

export function useProtocolLabel(): (protocol: string) => string {
  return (protocol) => protocol.toUpperCase();
}

export function SessionStatusBadge({
  status,
  expired,
}: {
  status: SessionRow["status"];
  expired: boolean;
}) {
  const label = useSessionStatusLabel();
  const t = useExtracted("checkoutSessions");

  if (expired) {
    return <Badge variant="secondary">{t("Expired")}</Badge>;
  }

  switch (status) {
    case "open": {
      return <Badge variant="info-light">{label(status)}</Badge>;
    }

    case "ready": {
      return <Badge variant="warning-light">{label(status)}</Badge>;
    }

    case "completed": {
      return <Badge variant="success-light">{label(status)}</Badge>;
    }

    case "canceled": {
      return <Badge variant="secondary">{label(status)}</Badge>;
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}
