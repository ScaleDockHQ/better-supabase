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
