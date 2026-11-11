"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { CollectionRow } from "../collection-row";

export function useScopeLabel(): (scope: string) => string {
  const t = useExtracted("collections");

  return (scope) => {
    switch (scope) {
      case "user": {
        return t("Personal");
      }

      case "team": {
        return t("Team");
      }

      case "tenant": {
        return t("Organization");
      }

      default: {
        return scope;
      }
    }
  };
}

export function useStateLabel(): (state: string) => string {
  const t = useExtracted("collections");

  return (state) => {
    switch (state) {
      case "active": {
        return t("Active");
      }

      case "archived": {
        return t("Archived");
      }

      default: {
        return state;
      }
    }
  };
}

export function CollectionScopeBadge({
  scope,
  archived,
}: {
  scope: CollectionRow["scope"];
  archived: boolean;
}) {
  const label = useScopeLabel();
  const state = useStateLabel();

  if (archived) {
    return <Badge variant="secondary">{state("archived")}</Badge>;
  }

  switch (scope) {
    case "user": {
      return <Badge variant="outline">{label(scope)}</Badge>;
    }

    case "team": {
      return <Badge variant="info-light">{label(scope)}</Badge>;
    }

    case "tenant": {
      return <Badge variant="success-light">{label(scope)}</Badge>;
    }

    default: {
      const never: never = scope;

      return never;
    }
  }
}
