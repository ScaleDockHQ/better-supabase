import type { RiskStatus } from "better-supabase/blocks/risks";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

/** The label of a risk status, for badges and filters. */
export function useRiskStatusLabel(): (status: string) => string {
  const t = useExtracted("risks");

  return (status) => {
    switch (status) {
      case "identified": {
        return t("Identified");
      }

      case "assessed": {
        return t("Assessed");
      }

      case "treating": {
        return t("Treating");
      }

      case "accepted": {
        return t("Accepted");
      }

      case "closed": {
        return t("Closed");
      }

      default: {
        return status;
      }
    }
  };
}

export function RiskStatusBadge({ status }: { status: RiskStatus }) {
  const label = useRiskStatusLabel();

  switch (status) {
    case "identified":
    case "closed": {
      return <Badge variant="secondary">{label(status)}</Badge>;
    }

    case "assessed": {
      return <Badge variant="info-light">{label(status)}</Badge>;
    }

    case "treating": {
      return <Badge variant="warning-light">{label(status)}</Badge>;
    }

    case "accepted": {
      return <Badge variant="success-light">{label(status)}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}
