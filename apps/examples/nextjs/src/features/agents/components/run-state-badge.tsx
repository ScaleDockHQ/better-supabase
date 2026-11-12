"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

/** The badge variant of a run's or step's state, by what it means. */
function stateVariant(status: string) {
  switch (status) {
    case "completed":
    case "done": {
      return "success-light";
    }

    case "failed":
    case "error": {
      return "destructive-light";
    }

    case "running":
    case "cancel_requested": {
      return "info-light";
    }

    case "queued":
    case "skipped":
    case "cancelled": {
      return "secondary";
    }

    default: {
      return "secondary";
    }
  }
}

/** A run or step state as a translated badge. */
export function RunStateBadge({ status }: { status: string }) {
  const t = useExtracted("agents");

  const label =
    status === "completed" || status === "done"
      ? t("Completed")
      : status === "failed" || status === "error"
        ? t("Failed")
        : status === "running"
          ? t("Running")
          : status === "queued"
            ? t("Queued")
            : status === "cancel_requested"
              ? t("Stopping")
              : status === "cancelled"
                ? t("Cancelled")
                : status === "skipped"
                  ? t("Skipped")
                  : status;

  return <Badge variant={stateVariant(status)}>{label}</Badge>;
}
