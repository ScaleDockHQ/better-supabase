"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

export function useTemplateActiveLabel() {
  const t = useExtracted("documents");

  return (value: string): string => {
    switch (value) {
      case "active": {
        return t("Active");
      }

      case "inactive": {
        return t("Inactive");
      }

      default: {
        return value;
      }
    }
  };
}

export function TemplateActiveBadge({ active }: { active: boolean }) {
  const label = useTemplateActiveLabel();

  return (
    <Badge variant={active ? "success-light" : "secondary"}>
      {label(active ? "active" : "inactive")}
    </Badge>
  );
}
