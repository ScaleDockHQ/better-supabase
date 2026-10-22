"use client";

import type { PreparationState } from "better-supabase/blocks/orders";

import { useExtracted } from "next-intl";

import type { BadgeProps } from "@/components/reui/badge";

export function preparationBadgeVariant(
  state: PreparationState,
): BadgeProps["variant"] {
  switch (state) {
    case "queued": {
      return "outline";
    }

    case "preparing": {
      return "warning-light";
    }

    case "ready": {
      return "success-light";
    }

    case "served": {
      return "secondary";
    }

    default: {
      const unknown: never = state;

      return unknown;
    }
  }
}

/** The state after `state`, or null once a line is served. */
export function nextPreparationState(
  state: PreparationState,
): PreparationState | null {
  switch (state) {
    case "queued": {
      return "preparing";
    }

    case "preparing": {
      return "ready";
    }

    case "ready": {
      return "served";
    }

    case "served": {
      return null;
    }

    default: {
      const unknown: never = state;

      return unknown;
    }
  }
}

export function usePreparationLabel(): (state: PreparationState) => string {
  const t = useExtracted("shop");

  return (state) => {
    switch (state) {
      case "queued": {
        return t("Queued");
      }

      case "preparing": {
        return t("Preparing");
      }

      case "ready": {
        return t("Ready");
      }

      case "served": {
        return t("Served");
      }

      default: {
        const unknown: never = state;

        return unknown;
      }
    }
  };
}
