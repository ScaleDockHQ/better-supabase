import type {
  IncidentSeverity,
  IncidentStatus,
} from "better-supabase/blocks/incidents";

type Variant =
  | "destructive-light"
  | "info-light"
  | "secondary"
  | "success-light"
  | "warning-light";

export const SEVERITY_VARIANT: Record<IncidentSeverity, Variant> = {
  sev1: "destructive-light",
  sev2: "warning-light",
  sev3: "info-light",
  sev4: "secondary",
};

export const STATUS_VARIANT: Record<IncidentStatus, Variant> = {
  investigating: "destructive-light",
  identified: "warning-light",
  monitoring: "info-light",
  resolved: "success-light",
};

export function statusLabel(
  t: (message: string) => string,
  status: IncidentStatus,
): string {
  switch (status) {
    case "investigating": {
      return t("Investigating");
    }

    case "identified": {
      return t("Identified");
    }

    case "monitoring": {
      return t("Monitoring");
    }

    case "resolved": {
      return t("Resolved");
    }

    default: {
      const unreachable: never = status;

      return unreachable;
    }
  }
}
