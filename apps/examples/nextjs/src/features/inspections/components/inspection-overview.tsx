import { ClipboardCheckIcon } from "lucide-react";
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

const inspectionsMap: EntityListMap = {
  sorts: { planned: { by: "plannedStart" }, number: { by: "number" } },
  filters: { f: "status" },
  facets: { f: "status" },
};

/** Keeps the item type of a block list that RLS already scopes. */
const unscoped = <Item,>(pager: EntityPager<Item>): EntityPager<Item> => pager;

async function statusCounts(): Promise<Readonly<Record<string, number>>> {
  const context = await overviewContext();

  if (context === null) {
    return {};
  }

  const facets = await context.db.inspections.facets({}).orThrow();
  const status = facets.find((facet) => facet.facet === "status");

  return Object.fromEntries(
    (status?.values ?? []).map((entry) => [entry.value, entry.count.value]),
  );
}

/** Inspections: the KPI band, then the searchable, paged register. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function InspectionOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("inspections.read");

  const [t, fmtDate, counts] = await Promise.all([
    getExtracted("inspections"),
    dateFormatter(),
    statusCounts(),
  ]);

  const statuses = {
    planned: t("Planned"),
    in_progress: t("In progress"),
    reporting: t("Reporting"),
    closed: t("Closed"),
    canceled: t("Canceled"),
  };

  const kpis = [
    { label: t("Planned"), value: String(counts["planned"] ?? 0) },
    { label: t("In progress"), value: String(counts["in_progress"] ?? 0) },
    { label: t("Reporting"), value: String(counts["reporting"] ?? 0) },
    { label: t("Closed"), value: String(counts["closed"] ?? 0) },
  ];

  return (
    <div className="flex flex-col gap-6">
      <KpiBand kpis={kpis} />
      <BlockOverview
        pager={({ db }) =>
          unscoped({
            page: (options) => db.inspections.page(options),
            facets: (options) => db.inspections.facets(options),
          })
        }
        map={inspectionsMap}
        query={query}
        toRow={(inspection) => ({
          id: inspection.id,
          number: inspection.number,
          title: inspection.title,
          status: inspection.status,
          plannedStart: fmtDate(inspection.plannedStart?.toString() ?? null),
        })}
        columns={[
          {
            key: "number",
            header: t("Inspection"),
            kind: "link",
            href: "/inspections/{id}",
            size: 150,
          },
          { key: "title", header: t("Title"), kind: "text", size: 300 },
          {
            key: "status",
            header: t("Status"),
            kind: "badge",
            size: 150,
            labels: statuses,
            tones: {
              planned: "secondary",
              in_progress: "info-light",
              reporting: "warning-light",
              closed: "success-light",
              canceled: "secondary",
            },
          },
          {
            key: "plannedStart",
            header: t("Planned start"),
            kind: "muted",
            size: 150,
          },
        ]}
        facet={{ key: "status", label: t("Status"), values: statuses }}
        sorts={[
          { value: "planned", label: t("Planned soonest") },
          { value: "number", label: t("Number") },
        ]}
        searchLabel={t("Search inspections")}
        errorTitle={t("The inspections didn't load")}
        emptyIcon={<ClipboardCheckIcon />}
        emptyTitle={t("No inspections yet")}
        emptyDescription={t(
          "Plan an inspection in the programme calendar, then run it here.",
        )}
      />
    </div>
  );
}
