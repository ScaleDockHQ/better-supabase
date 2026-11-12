"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { DeadlineRow } from "../deadlines-list";

/** A label for a stored value such as `not_covered`. */
export function useDeadlineLabel() {
  const t = useExtracted("work");

  return (value: string): string => {
    switch (value) {
      case "pending": {
        return t("Pending");
      }

      case "satisfied": {
        return t("Done");
      }

      case "due": {
        return t("Due");
      }

      case "unknown": {
        return t("Unknown");
      }

      default: {
        return value.replaceAll("_", " ");
      }
    }
  };
}

export function DeadlineStateBadge({ state }: { state: DeadlineRow["state"] }) {
  const label = useDeadlineLabel();

  return (
    <Badge variant={state === "satisfied" ? "success-light" : "warning-light"}>
      {label(state)}
    </Badge>
  );
}
