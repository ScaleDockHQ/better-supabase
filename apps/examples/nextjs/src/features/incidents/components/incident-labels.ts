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
