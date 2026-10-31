"use client";

import type {
  MeetingDecisionStatus,
  MeetingStatus,
} from "better-supabase/blocks/meetings";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

export function MeetingStatusBadge({ status }: { status: MeetingStatus }) {
  const t = useExtracted("meetings");

  switch (status) {
    case "planned": {
      return <Badge variant="secondary">{t("Planned")}</Badge>;
    }

    case "in_progress": {
      return <Badge variant="info-light">{t("In progress")}</Badge>;
    }

    case "held": {
      return <Badge variant="success-light">{t("Held")}</Badge>;
    }

    case "cancelled": {
      return <Badge variant="outline">{t("Canceled")}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

export function DecisionStatusBadge({
  status,
}: {
  status: MeetingDecisionStatus;
}) {
  const t = useExtracted("meetings");

  switch (status) {
    case "proposed": {
      return <Badge variant="secondary">{t("Proposed")}</Badge>;
    }

    case "passed": {
      return <Badge variant="success-light">{t("Passed")}</Badge>;
    }

    case "rejected": {
      return <Badge variant="destructive-light">{t("Rejected")}</Badge>;
    }

    case "deferred": {
      return <Badge variant="warning-light">{t("Deferred")}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

/** The default kinds in words; the app's own kinds show as stored. */
export function useKindLabel(): (kind: string) => string {
  const t = useExtracted("meetings");

  return (kind) => {
    switch (kind) {
      case "meeting": {
        return t("Meeting");
      }

      case "board": {
        return t("Board meeting");
      }

      case "management_review": {
        return t("Management review");
      }

      case "one_on_one": {
        return t("One-on-one");
      }

      case "toolbox_talk": {
        return t("Toolbox talk");
      }

      default: {
        return kind;
      }
    }
  };
}
