import { BoxesIcon, WarehouseIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { CreateLocationButton } from "@/features/shop/components/create-location-button";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";
import { pageBlockRows } from "@/lib/block-list";

import { stockList, stockSpec } from "../inventory-list";
import { getStock } from "../inventory-queries";
import { InventoryLoadError } from "./inventory-load-error";
import { StockRecordList } from "./stock-record-list";

function Kpi({
  label,
  value,
  hint,
}: {
  label: string;
  value: number;
  hint: string;
}) {
  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle className="text-sm font-medium text-muted-foreground">
          {label}
        </CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-1">
        <span className="text-2xl font-semibold tabular-nums">{value}</span>
        <span className="text-xs text-muted-foreground">{hint}</span>
      </CardContent>
    </Card>
  );
}

/**
 * Render inside `<Suspense>`: four counts as a KPI rail, then every stock level
 * on the list kit. An organization with no location sees the set-up action.
 */
export async function StockOverview() {
  const [t, permissions, stock] = await Promise.all([
    getExtracted("inventory"),
    getPermissions(),
    getStock(),
  ]);

  if (!can(permissions, "inventory.read")) {
    forbidden();
  }

  if (stock.kind === "no-organization") {
    return null;
  }

  if (stock.kind === "error") {
    return <InventoryLoadError title={t("The stock levels didn't load")} />;
  }

  const { locations, rows, lowCount, outCount, expiringCount, onHandTotal } =
    stock.data;

  if (locations.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <WarehouseIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No stock locations yet")}</EmptyTitle>
          <EmptyDescription>
            {t("Stock is counted per location. Add one to start.")}
          </EmptyDescription>
        </EmptyHeader>
        {can(permissions, "inventory.manage") ? (
          <EmptyContent>
            <CreateLocationButton />
          </EmptyContent>
        ) : null}
      </Empty>
    );
  }

  if (rows.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <BoxesIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No products to count")}</EmptyTitle>
          <EmptyDescription>
            {t("Products from the catalog show up here with their stock.")}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Link href="/shop" className={buttonVariants({ size: "sm" })}>
            {t("Go to the catalog")}
          </Link>
        </EmptyContent>
      </Empty>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Kpi
          label={t("Units on hand")}
          value={onHandTotal}
          hint={t("Across {count} levels", { count: String(rows.length) })}
        />
        <Kpi
          label={t("At or below reorder point")}
          value={lowCount}
          hint={t("Levels to order")}
        />
        <Kpi
          label={t("Out of stock")}
          value={outCount}
          hint={t("Nothing available to sell")}
        />
        <Kpi
          label={t("Lots expiring")}
          value={expiringCount}
          hint={t("Within 30 days")}
        />
      </div>
      <StockRecordList
        initial={pageBlockRows(stockList, stockSpec, rows, stockList.defaults)}
        locations={locations}
      />
    </div>
  );
}

export function StockOverviewSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Skeleton className="h-24 rounded-xl" />
        <Skeleton className="h-24 rounded-xl" />
        <Skeleton className="h-24 rounded-xl" />
        <Skeleton className="h-24 rounded-xl" />
      </div>
      <RecordListSkeleton rows={5} />
    </div>
  );
}
