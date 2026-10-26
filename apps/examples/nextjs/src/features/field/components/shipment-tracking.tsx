import type { ShipmentStatus } from "better-supabase/blocks/shipments";

import { PackageIcon, TruckIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden } from "next/navigation";
import { connection } from "next/server";
import * as v from "valibot";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardAction,
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
import { settle } from "@/features/people/people-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { loadShipmentTracking } from "../field-queries";
import { FieldLoadError } from "./field-load-error";
import { NewShipmentDialog } from "./new-shipment-dialog";

const ShipmentParam = v.pipe(v.string(), v.uuid());

async function ShipmentStatusBadge({ status }: { status: ShipmentStatus }) {
  const t = await getExtracted("field");

  switch (status) {
    case "draft": {
      return <Badge variant="secondary">{t("Draft")}</Badge>;
    }

    case "label_created": {
      return <Badge variant="info-light">{t("Label created")}</Badge>;
    }

    case "in_transit": {
      return <Badge variant="primary-light">{t("In transit")}</Badge>;
    }

    case "out_for_delivery": {
      return <Badge variant="primary-light">{t("Out for delivery")}</Badge>;
    }

    case "delivered": {
      return <Badge variant="success-light">{t("Delivered")}</Badge>;
    }

    case "exception": {
      return <Badge variant="warning-light">{t("Exception")}</Badge>;
    }

    case "returned": {
      return <Badge variant="warning-light">{t("Returned")}</Badge>;
    }

    case "cancelled": {
      return <Badge variant="destructive-light">{t("Cancelled")}</Badge>;
    }

    default: {
      const unhandled: never = status;

      return unhandled;
    }
  }
}

// #region recipe:shipment-tracking
/**
 * Render inside `<Suspense>`: the latest shipments with their status, and the
 * tracking timeline of the selected one, newest event first. `?shipment=<id>`
 * picks the shipment.
 */
export async function ShipmentTracking({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [t, format, query, permissions] = await Promise.all([
    getExtracted("field"),
    getFormatter(),
    searchParams,
    getPermissions(),
    connection(),
  ]);

  if (!can(permissions, "shipments.read")) {
    forbidden();
  }

  const picked = v.safeParse(ShipmentParam, query["shipment"]);

  const tracking = await settle(() =>
    loadShipmentTracking(picked.success ? picked.output : undefined),
  );

  if (tracking.kind === "no-organization") {
    return null;
  }

  const newShipment = can(permissions, "shipments.manage") ? (
    <NewShipmentDialog />
  ) : null;

  const selected = tracking.kind === "ok" ? tracking.data.selected : null;

  return (
    <div data-recipe="shipment-tracking" className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <CardTitle>{t("Shipments")}</CardTitle>
          <CardDescription>
            {t("The status follows the latest tracking event.")}
          </CardDescription>
          {newShipment ? <CardAction>{newShipment}</CardAction> : null}
        </CardHeader>
        <CardContent>
          {tracking.kind === "error" ? (
            <FieldLoadError title={t("The shipments didn't load")} />
          ) : tracking.data.shipments.length === 0 ? (
            <Empty className="border">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <PackageIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No shipments yet")}</EmptyTitle>
                <EmptyDescription>
                  {t("Create a shipment, then buy its label from a carrier.")}
                </EmptyDescription>
              </EmptyHeader>
              {newShipment ? <EmptyContent>{newShipment}</EmptyContent> : null}
            </Empty>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Reference")}</TableHead>
                  <TableHead>{t("Recipient")}</TableHead>
                  <TableHead>{t("Destination")}</TableHead>
                  <TableHead>{t("Tracking number")}</TableHead>
                  <TableHead>{t("Status")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {tracking.data.shipments.map((shipment) => (
                  <TableRow
                    key={shipment.id}
                    data-state={
                      shipment.id === selected?.id ? "selected" : undefined
                    }
                  >
                    <TableCell>
                      <Link
                        href={`/field/shipments?shipment=${shipment.id}`}
                        className="text-sm font-medium underline-offset-4 transition-colors hover:underline"
                        aria-current={
                          shipment.id === selected?.id ? "true" : undefined
                        }
                      >
                        {shipment.reference}
                      </Link>
                    </TableCell>
                    <TableCell className="text-sm">
                      {shipment.recipient}
                    </TableCell>
                    <TableCell className="text-sm text-muted-foreground">
                      {shipment.destination}
                    </TableCell>
                    <TableCell className="text-sm tabular-nums">
                      {shipment.trackingNumber ?? ""}
                    </TableCell>
                    <TableCell>
                      <ShipmentStatusBadge status={shipment.status} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
      {tracking.kind === "ok" && selected ? (
        <Card>
          <CardHeader>
            <CardTitle>
              {t("Tracking for {reference}", { reference: selected.reference })}
            </CardTitle>
            <CardDescription>
              {selected.carrier
                ? t("Events from {carrier}, newest first.", {
                    carrier: selected.carrier,
                  })
                : t("Events show once the shipment has a label.")}
            </CardDescription>
          </CardHeader>
          <CardContent>
            {tracking.data.timeline.length === 0 ? (
              <Empty className="border">
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <TruckIcon />
                  </EmptyMedia>
                  <EmptyTitle>{t("No tracking events yet")}</EmptyTitle>
                  <EmptyDescription>
                    {t(
                      "The carrier's webhook adds events as the package moves.",
                    )}
                  </EmptyDescription>
                </EmptyHeader>
                <EmptyContent>
                  <Link
                    href={`/field/shipments?shipment=${selected.id}`}
                    className="text-sm font-medium underline-offset-4 transition-colors hover:underline"
                  >
                    {t("Check again")}
                  </Link>
                </EmptyContent>
              </Empty>
            ) : (
              <ol className="flex flex-col divide-y">
                {tracking.data.timeline.map((step) => (
                  <li
                    key={step.id}
                    className="flex flex-wrap items-center gap-3 py-3"
                  >
                    <ShipmentStatusBadge status={step.status} />
                    <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                      <span className="text-sm">
                        {step.description ?? step.location ?? ""}
                      </span>
                      {step.description && step.location ? (
                        <span className="text-xs text-muted-foreground">
                          {step.location}
                        </span>
                      ) : null}
                    </div>
                    <span className="text-xs text-muted-foreground tabular-nums">
                      {format.dateTime(new Date(step.occurredAt), {
                        dateStyle: "medium",
                        timeStyle: "short",
                      })}
                    </span>
                  </li>
                ))}
              </ol>
            )}
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}
// #endregion recipe:shipment-tracking

export function ShipmentTrackingSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-64 rounded-xl" />
      <Skeleton className="h-48 rounded-xl" />
    </div>
  );
}
