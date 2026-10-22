import type {
  WorkOrderPriority,
  WorkOrderStatus,
} from "better-supabase/blocks/dispatch";

import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/reui/badge";

export async function WorkOrderStatusBadge({
  status,
}: {
  status: WorkOrderStatus;
}) {
  const t = await getExtracted("field");

  switch (status) {
    case "unscheduled": {
      return <Badge variant="secondary">{t("Unscheduled")}</Badge>;
    }

    case "scheduled": {
      return <Badge variant="info-light">{t("Scheduled")}</Badge>;
    }

    case "en_route": {
      return <Badge variant="primary-light">{t("En route")}</Badge>;
    }

    case "on_site": {
      return <Badge variant="warning-light">{t("On site")}</Badge>;
    }

    case "done": {
      return <Badge variant="success-light">{t("Done")}</Badge>;
    }

    case "cancelled": {
      return <Badge variant="destructive-light">{t("Cancelled")}</Badge>;
    }

    default: {
      const unhandled: never = status;

      return unhandled;
    }
  }
}

export async function WorkOrderPriorityBadge({
  priority,
}: {
  priority: WorkOrderPriority;
}) {
  const t = await getExtracted("field");

  switch (priority) {
    case "low": {
      return <Badge variant="outline">{t("Low")}</Badge>;
    }

    case "normal": {
      return <Badge variant="outline">{t("Normal")}</Badge>;
    }

    case "high": {
      return <Badge variant="warning-light">{t("High")}</Badge>;
    }

    case "urgent": {
      return <Badge variant="destructive-light">{t("Urgent")}</Badge>;
    }

    default: {
      const unhandled: never = priority;

      return unhandled;
    }
  }
}
