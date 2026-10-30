"use client";

import type {
  InspectionMemberRole,
  InspectionStatus,
} from "better-supabase/blocks/inspections";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

export function InspectionStatusBadge({
  status,
}: {
  status: InspectionStatus;
}) {
  const t = useExtracted("inspections");

  switch (status) {
    case "planned": {
      return <Badge variant="secondary">{t("Planned")}</Badge>;
    }

    case "in_progress": {
      return <Badge variant="info-light">{t("In progress")}</Badge>;
    }

    case "reporting": {
      return <Badge variant="warning-light">{t("Reporting")}</Badge>;
    }

    case "closed": {
      return <Badge variant="success-light">{t("Closed")}</Badge>;
    }

    case "canceled": {
      return <Badge variant="outline">{t("Canceled")}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

/** The default kinds in words; the app's own kinds show as stored. */
export function useKindLabel(): (kind: string) => string {
  const t = useExtracted("inspections");

  return (kind) => {
    switch (kind) {
      case "internal_audit": {
        return t("Internal audit");
      }

      case "external_audit": {
        return t("External audit");
      }

      case "supplier_audit": {
        return t("Supplier audit");
      }

      case "certification_audit": {
        return t("Certification audit");
      }

      case "inspection": {
        return t("Inspection");
      }

      default: {
        return kind;
      }
    }
  };
}

/** The default finding types in words; the app's own types show as stored. */
export function useFindingTypeLabel(): (type: string) => string {
  const t = useExtracted("inspections");

  return (type) => {
    switch (type) {
      case "major_nonconformity": {
        return t("Major nonconformity");
      }

      case "minor_nonconformity": {
        return t("Minor nonconformity");
      }

      case "observation": {
        return t("Observation");
      }

      case "opportunity": {
        return t("Opportunity");
      }

      case "positive": {
        return t("Positive");
      }

      default: {
        return type;
      }
    }
  };
}

export function useRoleLabel(): (role: InspectionMemberRole) => string {
  const t = useExtracted("inspections");

  return (role) => {
    switch (role) {
      case "lead": {
        return t("Lead");
      }

      case "auditor": {
        return t("Auditor");
      }

      case "observer": {
        return t("Observer");
      }

      case "auditee": {
        return t("Auditee");
      }

      default: {
        const unknown: never = role;

        return unknown;
      }
    }
  };
}
