"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { LotRow, StockStatus } from "../inventory-list";

export function useStockStatusLabel(): (status: string) => string {
  const t = useExtracted("inventory");

  return (status) => {
    switch (status) {
      case "in_stock": {
        return t("In stock");
      }

      case "low": {
        return t("Low");
      }

      case "out": {
        return t("Out of stock");
      }

      default: {
        return status;
      }
    }
  };
}

export function StockStatusBadge({ status }: { status: StockStatus }) {
  const label = useStockStatusLabel();

  switch (status) {
    case "in_stock": {
      return <Badge variant="success-light">{label(status)}</Badge>;
    }

    case "low": {
      return <Badge variant="warning-light">{label(status)}</Badge>;
    }

    case "out": {
      return <Badge variant="destructive-light">{label(status)}</Badge>;
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

export function useExpiryLabel(): (expiry: string) => string {
  const t = useExtracted("inventory");

  return (expiry) => {
    switch (expiry) {
      case "expired": {
        return t("Expired");
      }

      case "soon": {
        return t("Expires within 30 days");
      }

      case "later": {
        return t("Later");
      }

      default: {
        return expiry;
      }
    }
  };
}

export function ExpiryBadge({ expiry }: { expiry: LotRow["expiry"] }) {
  const label = useExpiryLabel();

  switch (expiry) {
    case "expired": {
      return <Badge variant="destructive-light">{label(expiry)}</Badge>;
    }

    case "soon": {
      return <Badge variant="warning-light">{label(expiry)}</Badge>;
    }

    case "later": {
      return <Badge variant="success-light">{label(expiry)}</Badge>;
    }

    default: {
      const never: never = expiry;

      return never;
    }
  }
}

/** The ledger's `stock.<reason>` kind in words. */
export function useMovementKindLabel(): (kind: string) => string {
  const t = useExtracted("inventory");

  return (kind) => {
    switch (kind) {
      case "stock.receipt": {
        return t("Receipt");
      }

      case "stock.adjustment": {
        return t("Adjustment");
      }

      case "stock.damage": {
        return t("Damage");
      }

      case "stock.loss": {
        return t("Loss");
      }

      case "stock.return": {
        return t("Return");
      }

      case "stock.scrap": {
        return t("Scrap");
      }

      case "stock.sale": {
        return t("Sale");
      }

      case "stock.count": {
        return t("Count");
      }

      case "stock.transfer": {
        return t("Transfer");
      }

      default: {
        return kind.replace(/^stock\./, "");
      }
    }
  };
}
