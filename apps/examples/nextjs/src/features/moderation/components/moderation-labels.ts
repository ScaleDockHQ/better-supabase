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

export function statusLabel(
  t: (message: string) => string,
  status: ModerationStatus,
): string {
  switch (status) {
    case "pending": {
      return t("Pending");
    }

    case "visible": {
      return t("Visible");
    }

    case "hidden": {
      return t("Hidden");
    }

    case "removed": {
      return t("Removed");
    }

    default: {
      const unreachable: never = status;

      return unreachable;
    }
  }
}
