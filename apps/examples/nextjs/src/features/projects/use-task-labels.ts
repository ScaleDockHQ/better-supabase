"use client";

import { useExtracted } from "next-intl";

import type { BadgeProps } from "@/components/reui/badge";

import type { TaskStatus, TaskView } from "./project-types";

export function statusBadgeVariant(status: TaskStatus): BadgeProps["variant"] {
  switch (status) {
    case "todo": {
      return "secondary";
    }

    case "doing": {
      return "info-light";
    }

    case "done": {
      return "success-light";
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

export function useStatusLabel(): (status: TaskStatus) => string {
  const t = useExtracted("projects");

  return (status) => {
    switch (status) {
      case "todo": {
        return t("To do");
      }

      case "doing": {
        return t("Doing");
      }

      case "done": {
        return t("Done");
      }

      default: {
        const unknown: never = status;

        return unknown;
      }
    }
  };
}

export function useViewLabel(): (view: TaskView) => string {
  const t = useExtracted("projects");

  return (view) => {
    switch (view) {
      case "table": {
        return t("Grid");
      }

      case "board": {
        return t("Board");
      }

      case "calendar": {
        return t("Calendar");
      }

      case "timeline": {
        return t("Timeline");
      }

      case "gantt": {
        return t("Gantt");
      }

      default: {
        const unknown: never = view;

        return unknown;
      }
    }
  };
}
