import type { FormStatus } from "better-supabase/blocks/forms";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

export function FormStatusBadge({ status }: { status: FormStatus }) {
  const t = useExtracted("forms");

  switch (status) {
    case "draft": {
      return <Badge variant="secondary">{t("Draft")}</Badge>;
    }

    case "open": {
      return <Badge variant="success-light">{t("Open")}</Badge>;
    }

    case "closed": {
      return <Badge variant="warning-light">{t("Closed")}</Badge>;
    }

    case "archived": {
      return <Badge variant="outline">{t("Archived")}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}
