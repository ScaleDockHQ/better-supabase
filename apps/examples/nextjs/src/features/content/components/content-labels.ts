import type { ContentStatus } from "better-supabase/blocks/content";

export const CONTENT_STATUS_VARIANT: Record<
  ContentStatus,
  "info-light" | "secondary" | "success-light" | "warning-light"
> = {
  draft: "secondary",
  scheduled: "info-light",
  published: "success-light",
  archived: "warning-light",
};
