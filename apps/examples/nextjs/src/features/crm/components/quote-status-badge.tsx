import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { QuoteStatus } from "../crm-queries";

export function QuoteStatusBadge({ status }: { status: QuoteStatus }) {
  const t = useExtracted("crm");

  switch (status) {
    case "draft": {
      return <Badge variant="secondary">{t("Draft")}</Badge>;
    }

    case "sent": {
      return <Badge variant="info-light">{t("Sent")}</Badge>;
    }

    case "viewed": {
      return <Badge variant="info-light">{t("Viewed")}</Badge>;
    }

    case "accepted": {
      return <Badge variant="success-light">{t("Accepted")}</Badge>;
    }

    case "rejected": {
      return <Badge variant="destructive-light">{t("Rejected")}</Badge>;
    }

    case "changes_requested": {
      return <Badge variant="warning-light">{t("Changes requested")}</Badge>;
    }

    case "expired": {
      return <Badge variant="outline">{t("Expired")}</Badge>;
    }

    case "withdrawn": {
      return <Badge variant="outline">{t("Withdrawn")}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}
