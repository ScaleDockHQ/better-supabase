import type { ModerationStatus } from "better-supabase/blocks/moderation";

export const STATUS_VARIANT: Record<
  ModerationStatus,
  "destructive-light" | "secondary" | "success-light" | "warning-light"
> = {
  pending: "warning-light",
  visible: "success-light",
  hidden: "secondary",
  removed: "destructive-light",
};
