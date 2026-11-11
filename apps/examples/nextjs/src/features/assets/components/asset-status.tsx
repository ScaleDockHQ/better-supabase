"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { AssetRow } from "../asset-row";

/** The label of an asset status, for the badge and the facet filter. */
export function useAssetStatusLabel(): (status: string) => string {
  const t = useExtracted("assets");

  return (status) => {
    switch (status) {
      case "active": {
        return t("In service");
      }

      case "maintenance": {
        return t("In maintenance");
      }

      case "retired": {
        return t("Retired");
      }

      default: {
        return status;
      }
    }
  };
}

export function AssetStatusBadge({ status }: { status: AssetRow["status"] }) {
  const label = useAssetStatusLabel();

  switch (status) {
    case "active": {
      return <Badge variant="success-light">{label(status)}</Badge>;
    }

    case "maintenance": {
      return <Badge variant="warning-light">{label(status)}</Badge>;
    }

    case "retired": {
      return <Badge variant="secondary">{label(status)}</Badge>;
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}
