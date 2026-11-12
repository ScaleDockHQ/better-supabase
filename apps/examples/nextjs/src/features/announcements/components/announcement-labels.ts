import type { AnnouncementSeverity } from "better-supabase/blocks/announcements";

export const ANNOUNCEMENT_VARIANT: Record<
  AnnouncementSeverity,
  "destructive-light" | "info-light" | "success-light" | "warning-light"
> = {
  info: "info-light",
  success: "success-light",
  warning: "warning-light",
  critical: "destructive-light",
};

export function severityLabel(
  t: (message: string) => string,
  severity: AnnouncementSeverity,
): string {
  switch (severity) {
    case "info": {
      return t("Info");
    }

    case "success": {
      return t("Success");
    }

    case "warning": {
      return t("Warning");
    }

    case "critical": {
      return t("Critical");
    }

    default: {
      const unreachable: never = severity;

      return unreachable;
    }
  }
}
