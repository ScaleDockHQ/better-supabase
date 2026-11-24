import { ClipboardListIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { unstable_rethrow } from "next/navigation";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { KpiBand, KpiBandSkeleton } from "@/components/record-list/kpi-band";
import { getClients } from "@/features/care/care-queries";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { BlockOverview } from "@/features/sales/components/block-overview";
import {
  dateFormatter,
  overviewContext,
  requirePermission,
} from "@/features/sales/components/overview-support";
import { facetTotals, totalOf } from "@/lib/facet-totals";

export { KpiBandSkeleton as CarePlanKpisSkeleton };

const carePlanMap = {
  sorts: {
    created: { by: "createdAt", direction: "desc" },
    title: { by: "title" },
    review: { by: "reviewOn" },
  },
  filters: { f: "status" },
  facets: { f: "status" },
} as const;

/** The figures above the list: plans by status, read in one facet call. */
// skeleton: the page's Suspense fallback is CarePlanKpisSkeleton
export async function CarePlanKpis() {
  await requirePermission("care_plans.read");

  const [t, context] = await Promise.all([
    getExtracted("care-plans"),
    overviewContext(),
  ]);

  if (context === null) {
    return null;
  }

  let totals: Readonly<Record<string, number>>;

  try {
    totals = facetTotals(
      await context.db.carePlans.facets({}).orThrow(),
      "status",
    );
  } catch (error) {
    unstable_rethrow(error);

    return <CrmLoadError title={t("The plan figures didn't load")} />;
  }

  return (
    <KpiBand
      kpis={[
        { label: t("Plans"), value: String(totalOf(totals)) },
        {
          label: t("Active"),
          value: String(totals["active"] ?? 0),
          href: "/care-plans?f=active",
        },
        {
          label: t("Drafts"),
          value: String(totals["draft"] ?? 0),
          href: "/care-plans?f=draft",
        },
        {
          label: t("Archived"),
          value: String(totals["archived"] ?? 0),
          href: "/care-plans?f=archived",
        },
      ]}
    />
  );
}

/** The plans of the organization, each opening its page. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CarePlanOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("care_plans.read");

  const [t, fmtDate, clients] = await Promise.all([
    getExtracted("care-plans"),
    dateFormatter(),
    getClients(),
  ]);

  const names = new Map(
    clients.kind === "ok"
      ? clients.data.map((client) => [client.id, client.name])
      : [],
  );

  const statusLabels = {
    draft: t("Draft"),
    active: t("Active"),
    archived: t("Archived"),
  };

  return (
    <BlockOverview
      pager={({ db }) => ({
        page: (options) => db.carePlans.page(options),
        facets: (options) => db.carePlans.facets(options),
      })}
      map={carePlanMap}
      query={query}
      toRow={(plan) => ({
        id: plan.id,
        title: plan.title,
        client: names.get(plan.subjectId) ?? "",
        version: `v${plan.version}`,
        status: plan.status,
        reviewOn: fmtDate(plan.reviewOn?.toString() ?? null),
      })}
      columns={[
        {
          key: "title",
          header: t("Plan"),
          kind: "link",
          href: "/care-plans/{id}",
          size: 280,
        },
        { key: "client", header: t("Client"), kind: "muted", size: 200 },
        { key: "version", header: t("Version"), kind: "muted", size: 90 },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 130,
          labels: statusLabels,
          tones: { active: "success-light", archived: "warning-light" },
        },
        { key: "reviewOn", header: t("Review on"), kind: "muted", size: 130 },
      ]}
      facet={{ key: "status", label: t("Status"), values: statusLabels }}
      sorts={[
        { value: "created", label: t("Newest") },
        { value: "review", label: t("Review date") },
        { value: "title", label: t("Title") },
      ]}
      searchLabel={t("Search plans")}
      errorTitle={t("The plans didn't load")}
      emptyIcon={<ClipboardListIcon />}
      emptyTitle={t("No plans found")}
      emptyDescription={t(
        "A plan holds a client's problems, goals and actions. Create one from the client's dossier.",
      )}
    />
  );
}
