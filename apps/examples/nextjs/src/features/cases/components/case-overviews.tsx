import { CircleCheckIcon, ClipboardListIcon, FlameIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { CountKpis } from "@/features/areas/components/count-kpis";
import { BlockOverview } from "@/features/sales/components/block-overview";
import {
  dateFormatter,
  requirePermission,
} from "@/features/sales/components/overview-support";

export function CaseListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}

/** The figures above the case list. */
// skeleton: the page's Suspense fallback is KpiBandSkeleton
export async function CaseKpis() {
  await requirePermission("cases.read");

  const t = await getExtracted("cases");

  return (
    <CountKpis
      sources={[
        {
          label: t("Open"),
          hint: t("Not yet closed"),
          icon: <ClipboardListIcon className="size-4" />,
          read: async (db) =>
            (await db.cases.count({ filters: { status: ["open"] } }).orThrow())
              .value,
        },
        {
          label: t("Closed"),
          hint: t("Verified and closed"),
          icon: <CircleCheckIcon className="size-4" />,
          read: async (db) =>
            (
              await db.cases
                .count({ filters: { status: ["closed"] } })
                .orThrow()
            ).value,
        },
        {
          label: t("All cases"),
          hint: t("Every kind, every stage"),
          icon: <FlameIcon className="size-4" />,
          read: async (db) => (await db.cases.count().orThrow()).value,
        },
      ]}
    />
  );
}

/** Every case as a server-paged table, filtered by status. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CaseOverview({ query }: { query: RecordListUrlQuery }) {
  await requirePermission("cases.read");

  const [t, fmtDate] = await Promise.all([
    getExtracted("cases"),
    dateFormatter(),
  ]);

  const statuses = { open: t("Open"), closed: t("Closed") };

  return (
    <BlockOverview
      pager={({ db }) => ({
        page: (options) => db.cases.page(options),
        facets: (options) => db.cases.facets(options),
      })}
      map={{
        sorts: {
          newest: { by: "createdAt", direction: "desc" },
          number: { by: "number" },
        },
        filters: { f: "status" },
        facets: { f: "status" },
      }}
      query={query}
      toRow={(item) => ({
        id: item.id,
        number: item.number,
        title: item.title,
        status: item.status,
        severity: item.severity ?? null,
        dueOn: fmtDate(item.dueOn?.toString()),
      })}
      columns={[
        { key: "number", header: t("Number"), kind: "muted", size: 140 },
        {
          key: "title",
          header: t("Case"),
          kind: "link",
          href: "/cases/{id}",
          size: 320,
        },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 110,
          labels: statuses,
          tones: { open: "warning-light", closed: "success-light" },
        },
        { key: "severity", header: t("Severity"), kind: "muted", size: 120 },
        { key: "dueOn", header: t("Due"), kind: "muted", size: 120 },
      ]}
      facet={{ key: "f", label: t("Status"), values: statuses }}
      sorts={[
        { value: "newest", label: t("Newest") },
        { value: "number", label: t("Number") },
      ]}
      errorTitle={t("The cases didn't load")}
      emptyIcon={<ClipboardListIcon />}
      emptyTitle={t("No cases yet")}
      emptyDescription={t("Report one from an inspection or a lab result.")}
    />
  );
}
