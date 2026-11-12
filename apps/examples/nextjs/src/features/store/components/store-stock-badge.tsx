import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/reui/badge";

import type { StoreStock } from "../store-queries";

// skeleton: renders from props and translations, so nothing of its own suspends
/** What a visitor sees of the stock: a bucket, never a count. */
export async function StoreStockBadge({ stock }: { stock: StoreStock }) {
  const t = await getExtracted("store");

  switch (stock) {
    case "in_stock": {
      return <Badge variant="success-light">{t("In stock")}</Badge>;
    }

    case "low": {
      return <Badge variant="warning-light">{t("Only a few left")}</Badge>;
    }

    case "out": {
      return <Badge variant="destructive-light">{t("Out of stock")}</Badge>;
    }

    default: {
      const never: never = stock;

      return never;
    }
  }
}
