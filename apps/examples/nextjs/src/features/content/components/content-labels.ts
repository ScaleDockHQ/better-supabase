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

export function contentStatusLabel(
  t: (message: string) => string,
  status: ContentStatus,
): string {
  switch (status) {
    case "draft": {
      return t("Draft");
    }

    case "scheduled": {
      return t("Scheduled");
    }

    case "published": {
      return t("Published");
    }

    case "archived": {
      return t("Archived");
    }

    default: {
      const unreachable: never = status;

      return unreachable;
    }
  }
}
