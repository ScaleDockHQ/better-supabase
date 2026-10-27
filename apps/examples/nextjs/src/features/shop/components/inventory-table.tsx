import { BoxesIcon, TriangleAlertIcon, WarehouseIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";
import { forbidden } from "next/navigation";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { getStockLevels } from "../shop-queries";
import { AdjustStockDialog } from "./adjust-stock-dialog";
import { CreateLocationButton } from "./create-location-button";

// #region recipe:inventory-table
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: stock per tracked variant and active location. */
export async function InventoryTable() {
  // The read starts with the permission check; RLS guards it either way.
  const [permissions, stock, t] = await Promise.all([
    getPermissions(),
    getStockLevels(),
    getExtracted("shop"),
  ]);

  if (!can(permissions, "inventory.read")) {
    forbidden();
  }

  if (stock.kind === "no-organization") {
    return null;
  }

  const canManage = can(permissions, "inventory.manage");

  const locationName = new Map(
    stock.kind === "ok"
      ? stock.data.locations.map((location) => [location.id, location.name])
      : [],
  );

  return (
    <Card data-recipe="inventory-table">
      <CardHeader>
        <CardTitle>{t("Stock levels")}</CardTitle>
        <CardDescription>
          {t(
            "Units on hand, reserved by open orders and available to sell, per location.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {stock.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The stock levels didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : stock.data.locations.length === 0 ? (
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
            {canManage ? (
              <EmptyContent>
                <CreateLocationButton />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : stock.data.levels.length === 0 ? (
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
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Product")}</TableHead>
                <TableHead>{t("Location")}</TableHead>
                <TableHead className="text-right">{t("On hand")}</TableHead>
                <TableHead className="text-right">{t("Reserved")}</TableHead>
                <TableHead className="text-right">{t("Available")}</TableHead>
                <TableHead>
                  <span className="sr-only">{t("Status")}</span>
                </TableHead>
                {canManage ? (
                  <TableHead>
                    <span className="sr-only">{t("Actions")}</span>
                  </TableHead>
                ) : null}
              </TableRow>
            </TableHeader>
            <TableBody>
              {stock.data.levels.map((level) => {
                const location = locationName.get(level.locationId) ?? "";

                return (
                  <TableRow key={`${level.variantId}:${level.locationId}`}>
                    <TableCell>
                      <div className="flex flex-col gap-1">
                        <span className="text-sm">{level.productTitle}</span>
                        <span className="font-mono text-xs text-muted-foreground">
                          {level.sku}
                        </span>
                      </div>
                    </TableCell>
                    <TableCell>{location}</TableCell>
                    <TableCell className="text-right tabular-nums">
                      {level.onHand}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {level.reserved}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {level.available}
                    </TableCell>
                    <TableCell>
                      {level.available <= 0 ? (
                        <Badge variant="destructive-light">
                          {t("Out of stock")}
                        </Badge>
                      ) : level.reorderPoint !== null &&
                        level.available <= level.reorderPoint ? (
                        <Badge variant="warning-light">{t("Low")}</Badge>
                      ) : (
                        <Badge variant="success-light">{t("In stock")}</Badge>
                      )}
                    </TableCell>
                    {canManage ? (
                      <TableCell className="text-right">
                        <AdjustStockDialog
                          variantId={level.variantId}
                          locationId={level.locationId}
                          label={`${level.productTitle} (${level.sku}), ${location}`}
                        />
                      </TableCell>
                    ) : null}
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:inventory-table

export function InventoryTableSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
