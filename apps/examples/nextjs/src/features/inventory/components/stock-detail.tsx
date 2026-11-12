import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Badge } from "@/components/reui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { AdjustStockDialog } from "@/features/shop/components/adjust-stock-dialog";
import { RequestPurchaseButton } from "@/features/shop/components/request-purchase-button";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { stockStatus } from "../inventory-list";
import { getStockItem } from "../inventory-queries";
import { InventoryLoadError } from "./inventory-load-error";
import { StockStatusBadge } from "./inventory-status";
import { StockMovementsCard } from "./stock-movements-card";

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="text-xs text-muted-foreground">{label}</span>
      <span className="text-sm font-medium tabular-nums">{value}</span>
    </div>
  );
}

/**
 * Render inside `<Suspense>`: one product's stock per location with its bins
 * and lots, then the newest ledger movements.
 */
export async function StockDetail({ variantId }: { variantId: string }) {
  const [t, format, permissions, loaded] = await Promise.all([
    getExtracted("inventory"),
    getFormatter(),
    getPermissions(),
    getStockItem(variantId),
  ]);

  if (!can(permissions, "inventory.read")) {
    forbidden();
  }

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <InventoryLoadError title={t("This product's stock didn't load")} />;
  }

  if (!loaded.data.found) {
    notFound();
  }

  const { productTitle, sku, locations, movements } = loaded.data;
  const canManage = can(permissions, "inventory.manage");

  const totalAvailable = locations.reduce(
    (sum, row) => sum + row.row.available,
    0,
  );

  const reorderTotal = locations.reduce(
    (sum, row) => sum + (row.row.reorderPoint ?? 0),
    0,
  );

  // The variant as a whole: out when nothing is available anywhere.
  const overall = stockStatus(
    totalAvailable,
    reorderTotal > 0 ? reorderTotal : null,
  );

  return (
    <RecordDetailFrame
      title={productTitle}
      description={sku}
      status={<StockStatusBadge status={overall} />}
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Across locations")}</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-2 gap-4">
            <Fact
              label={t("Available")}
              value={format.number(totalAvailable)}
            />
            <Fact
              label={t("On hand")}
              value={format.number(
                locations.reduce((sum, row) => sum + row.row.onHand, 0),
              )}
            />
            <Fact
              label={t("Reserved")}
              value={format.number(
                locations.reduce((sum, row) => sum + row.row.reserved, 0),
              )}
            />
            <Fact
              label={t("Incoming")}
              value={format.number(
                locations.reduce((sum, row) => sum + row.row.incoming, 0),
              )}
            />
          </CardContent>
        </Card>
      }
    >
      {locations.map(({ row, held, buckets }) => {
        const label = `${row.productTitle} (${row.sku}), ${row.locationName}`;

        const shortfall = Math.max(
          (row.reorderPoint ?? 5) * 2 - row.available,
          1,
        );

        return (
          <Card key={row.locationId} size="sm">
            <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2">
              <CardTitle>{row.locationName}</CardTitle>
              <div className="flex items-center gap-2">
                <StockStatusBadge status={row.status} />
                {canManage ? (
                  <>
                    {row.status === "in_stock" ? null : (
                      <RequestPurchaseButton
                        variantId={row.variantId}
                        locationId={row.locationId}
                        quantity={shortfall}
                        label={label}
                      />
                    )}
                    <AdjustStockDialog
                      variantId={row.variantId}
                      locationId={row.locationId}
                      label={label}
                    />
                  </>
                ) : null}
              </div>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-5">
                <Fact label={t("On hand")} value={format.number(row.onHand)} />
                <Fact
                  label={t("Reserved")}
                  value={format.number(row.reserved)}
                />
                <Fact label={t("On hold")} value={format.number(held)} />
                <Fact
                  label={t("Available")}
                  value={format.number(row.available)}
                />
                <Fact
                  label={t("Reorder point")}
                  value={
                    row.reorderPoint === null
                      ? "–"
                      : format.number(row.reorderPoint)
                  }
                />
              </div>
              {buckets.some(
                (bucket) => (bucket.lotId ?? bucket.binId) !== null,
              ) ? (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t("Lot")}</TableHead>
                      <TableHead>{t("Bin")}</TableHead>
                      <TableHead>{t("Expires")}</TableHead>
                      <TableHead className="text-right">
                        {t("On hand")}
                      </TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {buckets.map((bucket) => (
                      <TableRow
                        key={`${bucket.lotId ?? ""}:${bucket.binId ?? ""}`}
                      >
                        <TableCell className="font-mono">
                          {bucket.lotCode ?? "–"}
                        </TableCell>
                        <TableCell>
                          {bucket.binCode ?? "–"}
                          {bucket.hold ? (
                            <Badge variant="warning-light" className="ml-2">
                              {t("On hold")}
                            </Badge>
                          ) : null}
                        </TableCell>
                        <TableCell>
                          {bucket.expiresOn === null
                            ? "–"
                            : format.dateTime(
                                new Date(`${bucket.expiresOn}T00:00:00`),
                                { dateStyle: "medium" },
                              )}
                        </TableCell>
                        <TableCell className="text-right tabular-nums">
                          {format.number(bucket.onHand)}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              ) : null}
            </CardContent>
          </Card>
        );
      })}
      <StockMovementsCard movements={movements} />
    </RecordDetailFrame>
  );
}

export function StockDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-10 w-72" />
      <RecordSectionSkeleton rows={3} />
      <RecordSectionSkeleton rows={4} />
    </div>
  );
}
