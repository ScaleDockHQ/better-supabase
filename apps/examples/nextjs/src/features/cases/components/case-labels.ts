"use client";

import type { CaseActionType, CaseBlocker } from "better-supabase/blocks/cases";

import { useExtracted } from "next-intl";

import type { OpenStage } from "../cases-stages";

/** The Badge variant of a severity; the app's own severities read as outline. */
export function severityVariant(
  severity: string,
):
  | "secondary"
  | "warning-light"
  | "destructive-light"
  | "destructive"
  | "outline" {
  switch (severity) {
    case "low": {
      return "secondary";
    }

    case "medium": {
      return "warning-light";
    }

    case "high": {
      return "destructive-light";
    }

    case "critical": {
      return "destructive";
    }

    default: {
      return "outline";
    }
  }
}

/** The default severities in words; the app's own ones show as stored. */
export function useSeverityLabel(): (severity: string) => string {
  const t = useExtracted("cases");

  return (severity) => {
    switch (severity) {
      case "low": {
        return t("Low");
      }

      case "medium": {
        return t("Medium");
      }

      case "high": {
        return t("High");
      }

      case "critical": {
        return t("Critical");
      }

      default: {
        return severity;
      }
    }
  };
}

export function useStageLabel(): (stage: OpenStage) => string {
  const t = useExtracted("cases");

  return (stage) => {
    switch (stage) {
      case "reported": {
        return t("Reported");
      }

      case "investigating": {
        return t("Investigating");
      }

      case "acting": {
        return t("Acting");
      }

      case "verifying": {
        return t("Verifying");
      }

      default: {
        const unknown: never = stage;

        return unknown;
      }
    }
  };
}

export function useBlockerLabel(): (blocker: CaseBlocker) => string {
  const t = useExtracted("cases");

  return (blocker) => {
    switch (blocker) {
      case "CASE_ROOT_CAUSE_REQUIRED": {
        return t("Record the root cause.");
      }

      case "CASE_ACTIONS_REQUIRED": {
        return t("Add at least one required action.");
      }

      case "CASE_ACTIONS_OPEN": {
        return t("Finish the open required actions.");
      }

      case "CASE_EFFECTIVENESS_REQUIRED": {
        return t("Record whether the actions worked.");
      }

      case "CASE_DOCUMENTS_NOT_REVISED": {
        return t("Publish a new version of the affected documents.");
      }

      default: {
        const unknown: never = blocker;

        return unknown;
      }
    }
  };
}

export function useActionTypeLabel(): (type: CaseActionType) => string {
  const t = useExtracted("cases");

  return (type) => {
    switch (type) {
      case "containment": {
        return t("Containment");
      }

      case "correction": {
        return t("Correction");
      }

      case "corrective": {
        return t("Corrective");
      }

      case "preventive": {
        return t("Preventive");
      }

      case "improvement": {
        return t("Improvement");
      }

      default: {
        const unknown: never = type;

        return unknown;
      }
    }
  };
}
