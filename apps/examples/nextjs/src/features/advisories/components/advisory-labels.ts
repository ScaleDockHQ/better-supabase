import type { AdvisoryStatus } from "better-supabase/blocks/advisories";

export const ADVISORY_STATUS_VARIANT: Record<
  AdvisoryStatus,
  "info-light" | "secondary" | "success-light"
> = { draft: "secondary", interim: "info-light", final: "success-light" };

export function severityVariant(
  severity: string | null,
): "destructive-light" | "info-light" | "secondary" | "warning-light" {
  if (severity === null) {
    return "secondary";
  }

  switch (severity) {
    case "critical":
    case "high": {
      return "destructive-light";
    }

    case "medium": {
      return "warning-light";
    }

    case "low": {
      return "info-light";
    }

    default: {
      return "secondary";
    }
  }
}
