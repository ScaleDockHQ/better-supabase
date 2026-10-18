import type { OrderStatus } from "better-supabase/blocks/orders";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

export function OrderStatusBadge({
  status,
}: {
  status: OrderStatus | "draft";
}) {
  const t = useExtracted("shop");

  switch (status) {
    case "draft": {
      return <Badge variant="secondary">{t("Draft")}</Badge>;
    }

    case "pending_payment": {
      return <Badge variant="warning-light">{t("Awaiting payment")}</Badge>;
    }

    case "paid": {
      return <Badge variant="info-light">{t("Paid")}</Badge>;
    }

    case "fulfilled": {
      return <Badge variant="primary-light">{t("Fulfilled")}</Badge>;
    }

    case "completed": {
      return <Badge variant="success-light">{t("Completed")}</Badge>;
    }

    case "cancelled": {
      return <Badge variant="destructive-light">{t("Cancelled")}</Badge>;
    }

    case "refunded": {
      return <Badge variant="invert-light">{t("Refunded")}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}
