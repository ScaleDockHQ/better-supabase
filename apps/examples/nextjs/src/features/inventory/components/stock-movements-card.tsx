"use client";

import { useExtracted, useFormatter } from "next-intl";

import { Badge } from "@/components/reui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Link } from "@/i18n/navigation";

import type { MovementRow } from "../inventory-list";

import { useMovementKindLabel } from "./inventory-status";

/** The newest ledger movements of one variant. */
export function StockMovementsCard({
  movements,
}: {
  movements: readonly MovementRow[];
}) {
  const t = useExtracted("inventory");
  const format = useFormatter();
  const kindLabel = useMovementKindLabel();

  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>{t("Recent movements")}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {movements.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("No movement has been written for this product yet.")}
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("When")}</TableHead>
                <TableHead>{t("Location")}</TableHead>
                <TableHead>{t("Kind")}</TableHead>
                <TableHead className="text-right">{t("Quantity")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {movements.slice(0, 20).map((movement) => (
                <TableRow key={movement.id}>
                  <TableCell className="text-muted-foreground">
                    {format.dateTime(new Date(movement.effectiveAt), {
                      dateStyle: "medium",
                      timeStyle: "short",
                    })}
                  </TableCell>
                  <TableCell>{movement.locationName}</TableCell>
                  <TableCell>
                    <Badge variant="outline">{kindLabel(movement.kind)}</Badge>
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {movement.quantity > 0
                      ? `+${movement.quantity}`
                      : movement.quantity}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
        <Link
          href="/shop/inventory/movements"
          className="w-fit text-sm text-muted-foreground hover:underline"
        >
          {t("All movements")}
        </Link>
      </CardContent>
    </Card>
  );
}
