import { FactoryIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";
import type { EntityListMap, EntityPager } from "@/lib/block-entity-page";

import { KpiBand } from "@/components/record-list/kpi-band";
import { BlockOverview } from "@/features/sales/components/block-overview";
import {
  dateFormatter,
  overviewContext,
  requirePermission,
} from "@/features/sales/components/overview-support";

const ordersMap: EntityListMap = {
  sorts: {
    due: { by: "dueOn" },
    newest: { by: "createdAt", direction: "desc" },
    number: { by: "number" },
  },
  filters: { f: "status" },
  facets: { f: "status" },
};

/** Keeps the item type of a block list that RLS already scopes. */
const unscoped = <Item,>(pager: EntityPager<Item>): EntityPager<Item> => pager;

/** How many production orders hold each status, from the block's facet. */
async function statusCounts(): Promise<Readonly<Record<string, number>>> {
  const context = await overviewContext();

  if (context === null) {
    return {};
  }

  const facets = await context.db.manufacturing.orderFacets().orThrow();
  const status = facets.find((facet) => facet.facet === "status");

  return Object.fromEntries(
    (status?.values ?? []).map((entry) => [entry.value, entry.count.value]),
  );
}

/** Production orders: the KPI band, then the searchable, paged list. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ProductionOrderOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("manufacturing.read");

  const [t, fmtDate, counts] = await Promise.all([
    getExtracted("manufacturing"),
    dateFormatter(),
    statusCounts(),
  ]);

  const statuses = {
    draft: t("Draft"),
    released: t("Released"),
    in_progress: t("In progress"),
    done: t("Done"),
    canceled: t("Canceled"),
  };

  const kpis = [
    { label: t("Draft"), value: String(counts["draft"] ?? 0) },
    { label: t("Released"), value: String(counts["released"] ?? 0) },
    { label: t("In progress"), value: String(counts["in_progress"] ?? 0) },
    { label: t("Done"), value: String(counts["done"] ?? 0) },
  ];

  return (
    <div className="flex flex-col gap-6">
      <KpiBand kpis={kpis} />
      <BlockOverview
        pager={({ db }) =>
          unscoped({
            page: (options) => db.manufacturing.orderPage(options),
            facets: (options) => db.manufacturing.orderFacets(options),
          })
        }
        map={ordersMap}
        query={query}
        toRow={(order) => ({
          id: order.id,
          order: order.number,
          quantity: `${String(order.producedQuantity)} / ${String(order.quantity)}`,
          status: order.status,
          dueOn: fmtDate(order.dueOn?.toString() ?? null),
        })}
        columns={[
          {
            key: "order",
            header: t("Order"),
            kind: "link",
            href: "/manufacturing/orders/{id}",
            size: 160,
          },
          {
            key: "quantity",
            header: t("Produced / planned"),
            kind: "number",
            size: 180,
          },
          {
            key: "status",
            header: t("Status"),
            kind: "badge",
            size: 160,
            labels: statuses,
            tones: {
              draft: "secondary",
              released: "info-light",
              in_progress: "warning-light",
              done: "success-light",
              canceled: "secondary",
            },
          },
          { key: "dueOn", header: t("Due"), kind: "muted", size: 140 },
        ]}
        facet={{ key: "status", label: t("Status"), values: statuses }}
        sorts={[
          { value: "due", label: t("Due soonest") },
          { value: "newest", label: t("Newest first") },
          { value: "number", label: t("Number") },
        ]}
        searchLabel={t("Search production orders")}
        errorTitle={t("The production orders didn't load")}
        emptyIcon={<FactoryIcon />}
        emptyTitle={t("No production orders yet")}
        emptyDescription={t(
          "Create orders from the plan board, then release and complete them here.",
        )}
      />
    </div>
  );
}
