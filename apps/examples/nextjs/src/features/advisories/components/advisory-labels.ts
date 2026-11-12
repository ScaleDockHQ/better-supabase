import type { AdvisoryStatus } from "better-supabase/blocks/advisories";

export const ADVISORY_STATUS_VARIANT: Record<
  AdvisoryStatus,
  "info-light" | "secondary" | "success-light"
> = { draft: "secondary", interim: "info-light", final: "success-light" };

export function advisoryStatusLabel(
  t: (message: string) => string,
  status: AdvisoryStatus,
): string {
  switch (status) {
    case "draft": {
      return t("Draft");
    }

    case "interim": {
      return t("Interim");
    }

    case "final": {
      return t("Final");
    }

    default: {
      const unreachable: never = status;

      return unreachable;
    }
  }
}

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
