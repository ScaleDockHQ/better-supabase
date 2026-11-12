"use client";

import type { DriveDocumentStatus } from "better-supabase/blocks/drive";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

export function useRegisterStatusLabel() {
  const t = useExtracted("documents");

  return (value: string): string => {
    switch (value) {
      case "draft": {
        return t("Draft");
      }

      case "in_review": {
        return t("In review");
      }

      case "effective": {
        return t("Effective");
      }

      case "obsolete": {
        return t("Obsolete");
      }

      case "due": {
        return t("Review due");
      }

      case "ok": {
        return t("On schedule");
      }

      default: {
        return value;
      }
    }
  };
}

const VARIANT = {
  draft: "secondary",
  in_review: "info-light",
  effective: "success-light",
  obsolete: "secondary",
} as const satisfies Record<DriveDocumentStatus, string>;

export function RegisterStatusBadge({
  status,
}: {
  status: DriveDocumentStatus;
}) {
  const label = useRegisterStatusLabel();

  return <Badge variant={VARIANT[status]}>{label(status)}</Badge>;
}
