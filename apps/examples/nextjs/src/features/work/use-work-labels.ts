"use client";

import type { WorkItemState } from "better-supabase/blocks/work-items";

import { useExtracted } from "next-intl";

import type { BadgeProps } from "@/components/reui/badge";

/** The badge each state gets, by meaning: done is success, canceled is muted. */
export function stateBadgeVariant(state: string): BadgeProps["variant"] {
  switch (state) {
    case "triage": {
      return "warning-light";
    }

    case "backlog":
    case "unstarted": {
      return "secondary";
    }

    case "started": {
      return "info-light";
    }

    case "completed": {
      return "success-light";
    }

    case "canceled": {
      return "outline";
    }

    default: {
      return "secondary";
    }
  }
}

export function useStateLabel(): (state: WorkItemState) => string {
  const t = useExtracted("work");

  return (state) => {
    switch (state) {
      case "triage": {
        return t("Triage");
      }

      case "backlog": {
        return t("Backlog");
      }

      case "unstarted": {
        return t("To do");
      }

      case "started": {
        return t("In progress");
      }

      case "completed": {
        return t("Done");
      }

      case "canceled": {
        return t("Canceled");
      }

      default: {
        const unknown: never = state;

        return unknown;
      }
    }
  };
}

export function usePriorityLabel(): (priority: number) => string {
  const t = useExtracted("work");

  return (priority) => {
    switch (priority) {
      case 1: {
        return t("Urgent");
      }

      case 2: {
        return t("High");
      }

      case 3: {
        return t("Medium");
      }

      case 4: {
        return t("Low");
      }

      default: {
        return t("No priority");
      }
    }
  };
}

/** The message for a work action error the pipelines trigger raised. */
export function useWorkErrorHint(): (
  hint: string | undefined,
) => string | null {
  const t = useExtracted("work");

  return (hint) =>
    hint === "PIPELINE_TRANSITION_INVALID"
      ? t("The workflow doesn't allow that move.")
      : null;
}
