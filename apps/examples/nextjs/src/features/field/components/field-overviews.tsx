import {
  AlertTriangleIcon,
  CalendarClockIcon,
  PackageIcon,
  TruckIcon,
  WrenchIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { CountKpis } from "@/features/areas/components/count-kpis";
import { BlockOverview } from "@/features/sales/components/block-overview";
import {
  dateFormatter,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { NewShipmentDialog } from "./new-shipment-dialog";

export function FieldListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}

/** The figures above the work order list. */
// skeleton: the page's Suspense fallback is KpiBandSkeleton
export async function WorkOrderKpis() {
  await requirePermission("dispatch.read");

  const t = await getExtracted("field");

  return (
    <CountKpis
      sources={[
        {
          label: t("Backlog"),
          hint: t("Waiting to be scheduled"),
          icon: <CalendarClockIcon className="size-4" />,
          read: async (db) =>
            (
              await db.dispatch
                .count({ filters: { status: ["unscheduled"] } })
                .orThrow()
            ).value,
        },
        {
          label: t("Scheduled"),
          hint: t("In a technician's day"),
          icon: <WrenchIcon className="size-4" />,
          read: async (db) =>
            (
              await db.dispatch
                .count({ filters: { status: ["scheduled"] } })
                .orThrow()
            ).value,
        },
        {
          label: t("In progress"),
          hint: t("En route or on site"),
          icon: <TruckIcon className="size-4" />,
          read: async (db) =>
            (
              await db.dispatch
                .count({ filters: { status: ["en_route", "on_site"] } })
                .orThrow()
            ).value,
        },
        {
          label: t("Urgent"),
          hint: t("Urgent priority, not yet done"),
          icon: <AlertTriangleIcon className="size-4" />,
          read: async (db) =>
            (
              await db.dispatch
                .count({ filters: { priority: ["urgent"] } })
                .orThrow()
            ).value,
        },
      ]}
    />
  );
}

/** Every work order as a server-paged table, filtered by status. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function WorkOrderOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("dispatch.read");

  const [t, fmtDate] = await Promise.all([
    getExtracted("field"),
    dateFormatter(),
  ]);

  const statuses = {
    unscheduled: t("Unscheduled"),
    scheduled: t("Scheduled"),
    en_route: t("En route"),
    on_site: t("On site"),
    done: t("Done"),
    cancelled: t("Cancelled"),
  };

  return (
    <BlockOverview
      pager={({ db }) => ({
        page: (options) => db.dispatch.page(options),
        facets: (options) => db.dispatch.facets(options),
      })}
      map={{
        sorts: {
          newest: { by: "createdAt", direction: "desc" },
          start: { by: "startsAt", direction: "desc" },
          title: { by: "title" },
        },
        filters: { f: "status" },
        facets: { f: "status" },
      }}
      query={query}
      toRow={(order) => ({
        id: order.id,
        title: order.title,
        status: order.status,
        priority: order.priority,
        startsAt: fmtDate(order.startsAt?.toString()),
        address: order.address ?? null,
      })}
      columns={[
        {
          key: "title",
          header: t("Job"),
          kind: "link",
          href: "/field/dispatch/{id}",
          size: 260,
        },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 130,
          labels: statuses,
          tones: {
            unscheduled: "secondary",
            scheduled: "info-light",
            en_route: "primary-light",
            on_site: "warning-light",
            done: "success-light",
            cancelled: "destructive-light",
          },
        },
        {
          key: "priority",
          header: t("Priority"),
          kind: "badge",
          size: 110,
          labels: {
            low: t("Low"),
            normal: t("Normal"),
            high: t("High"),
            urgent: t("Urgent"),
          },
          tones: { high: "warning-light", urgent: "destructive-light" },
        },
        { key: "startsAt", header: t("Starts"), kind: "muted", size: 130 },
        { key: "address", header: t("Address"), kind: "muted", size: 240 },
      ]}
      facet={{ key: "f", label: t("Status"), values: statuses }}
      sorts={[
        { value: "newest", label: t("Newest") },
        { value: "start", label: t("Start date") },
        { value: "title", label: t("Job") },
      ]}
      errorTitle={t("The work orders didn't load")}
      emptyIcon={<WrenchIcon />}
      emptyTitle={t("No work orders yet")}
      emptyDescription={t("Open one from the dispatch board.")}
    />
  );
}

/** The figures above the shipment list. */
// skeleton: the page's Suspense fallback is KpiBandSkeleton
export async function ShipmentKpis() {
  await requirePermission("shipments.read");

  const t = await getExtracted("field");

  return (
    <CountKpis
      sources={[
        {
          label: t("Drafts"),
          hint: t("No label yet"),
          icon: <PackageIcon className="size-4" />,
          read: async (db) =>
            (
              await db.shipments
                .shipmentCount({ filters: { status: ["draft"] } })
                .orThrow()
            ).value,
        },
        {
          label: t("In transit"),
          hint: t("With the carrier"),
          icon: <TruckIcon className="size-4" />,
          read: async (db) =>
            (
              await db.shipments
                .shipmentCount({
                  filters: { status: ["in_transit", "out_for_delivery"] },
                })
                .orThrow()
            ).value,
        },
        {
          label: t("Delivered"),
          icon: <PackageIcon className="size-4" />,
          read: async (db) =>
            (
              await db.shipments
                .shipmentCount({ filters: { status: ["delivered"] } })
                .orThrow()
            ).value,
        },
        {
          label: t("Exceptions"),
          hint: t("Needs a look"),
          icon: <AlertTriangleIcon className="size-4" />,
          read: async (db) =>
            (
              await db.shipments
                .shipmentCount({ filters: { status: ["exception"] } })
                .orThrow()
            ).value,
        },
      ]}
    />
  );
}

/** Every shipment as a server-paged table. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ShipmentOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("shipments.read");

  const [t, fmtDate] = await Promise.all([
    getExtracted("field"),
    dateFormatter(),
  ]);

  const statuses = {
    draft: t("Draft"),
    label_created: t("Label created"),
    in_transit: t("In transit"),
    out_for_delivery: t("Out for delivery"),
    delivered: t("Delivered"),
    exception: t("Exception"),
    returned: t("Returned"),
    cancelled: t("Cancelled"),
  };

  return (
    <BlockOverview
      pager={({ db }) => ({
        page: (options) => db.shipments.shipmentPage(options),
        facets: (options) => db.shipments.shipmentFacets(options),
      })}
      map={{
        sorts: { newest: { by: "createdAt", direction: "desc" } },
        filters: { f: "status" },
        facets: { f: "status" },
      }}
      query={query}
      searchLabel={t("Search reference or tracking number")}
      toRow={(shipment) => ({
        id: shipment.id,
        reference: shipment.reference,
        status: shipment.status,
        recipient: shipment.to.name ?? shipment.to.company ?? null,
        destination: `${shipment.to.city}, ${shipment.to.country}`,
        carrier: shipment.carrier ?? null,
        updatedAt: fmtDate(shipment.updatedAt.toString()),
      })}
      columns={[
        {
          key: "reference",
          header: t("Reference"),
          kind: "link",
          href: "/field/shipments/{id}",
          size: 160,
        },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 150,
          labels: statuses,
          tones: {
            draft: "secondary",
            label_created: "info-light",
            in_transit: "primary-light",
            out_for_delivery: "primary-light",
            delivered: "success-light",
            exception: "destructive-light",
            returned: "warning-light",
            cancelled: "destructive-light",
          },
        },
        { key: "recipient", header: t("Recipient"), kind: "text", size: 200 },
        {
          key: "destination",
          header: t("Destination"),
          kind: "muted",
          size: 180,
        },
        { key: "carrier", header: t("Carrier"), kind: "muted", size: 120 },
        { key: "updatedAt", header: t("Updated"), kind: "muted", size: 130 },
      ]}
      facet={{ key: "f", label: t("Status"), values: statuses }}
      sorts={[{ value: "newest", label: t("Newest") }]}
      errorTitle={t("The shipments didn't load")}
      emptyIcon={<PackageIcon />}
      emptyTitle={t("No shipments yet")}
      emptyDescription={t("Create one to start tracking a parcel.")}
      emptyAction={<NewShipmentDialog />}
    />
  );
}
