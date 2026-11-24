import { FileTextIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { unstable_rethrow } from "next/navigation";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { KpiBand, KpiBandSkeleton } from "@/components/record-list/kpi-band";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { BlockOverview } from "@/features/sales/components/block-overview";
import {
  dateFormatter,
  holds,
  overviewContext,
  requirePermission,
} from "@/features/sales/components/overview-support";
import { facetTotals, totalOf } from "@/lib/facet-totals";

import { CreateEntryDialog } from "./create-entry-dialog";

export { KpiBandSkeleton as ContentKpisSkeleton };

/** What the content list's URL names stand for on the block's `page`. */
const contentMap = {
  sorts: {
    updated: { by: "updatedAt", direction: "desc" },
    title: { by: "title" },
    published: { by: "publishedAt", direction: "desc" },
  },
  filters: { f: "status" },
  facets: { f: "status" },
} as const;

/** The figures above the list: entries by status, read in one facet call. */
// skeleton: the page's Suspense fallback is ContentKpisSkeleton
export async function ContentKpis() {
  await requirePermission("content.read");

  const [t, context] = await Promise.all([
    getExtracted("content"),
    overviewContext(),
  ]);

  if (context === null) {
    return null;
  }

  let totals: Readonly<Record<string, number>>;

  try {
    totals = facetTotals(
      await context.db.content.facets({}).orThrow(),
      "status",
    );
  } catch (error) {
    unstable_rethrow(error);

    return <CrmLoadError title={t("The content figures didn't load")} />;
  }

  return (
    <KpiBand
      kpis={[
        { label: t("Entries"), value: String(totalOf(totals)) },
        {
          label: t("Published"),
          value: String(totals["published"] ?? 0),
          href: "/content?f=published",
        },
        {
          label: t("Scheduled"),
          value: String(totals["scheduled"] ?? 0),
          href: "/content?f=scheduled",
        },
        {
          label: t("Drafts"),
          value: String(totals["draft"] ?? 0),
          href: "/content?f=draft",
        },
      ]}
    />
  );
}

/** The entries, searchable and filtered by status, each opening its page. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ContentOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("content.read");

  const [t, fmtDate, canWrite] = await Promise.all([
    getExtracted("content"),
    dateFormatter(),
    holds("content.write"),
  ]);

  const statusLabels = {
    draft: t("Draft"),
    scheduled: t("Scheduled"),
    published: t("Published"),
    archived: t("Archived"),
  };

  return (
    <BlockOverview
      pager={({ db }) => ({
        page: (options) => db.content.page(options),
        facets: (options) => db.content.facets(options),
      })}
      map={contentMap}
      query={query}
      toRow={(entry) => ({
        id: entry.id,
        title: entry.title,
        slug: `/${entry.slug}`,
        type: entry.type,
        locale: entry.locale,
        status: entry.status,
        updatedAt: fmtDate(entry.updatedAt.toString()),
      })}
      columns={[
        {
          key: "title",
          header: t("Title"),
          kind: "link",
          href: "/content/{id}",
          size: 280,
        },
        { key: "slug", header: t("Slug"), kind: "muted", size: 200 },
        {
          key: "type",
          header: t("Type"),
          kind: "badge",
          size: 100,
          labels: { page: t("Page"), post: t("Post") },
        },
        { key: "locale", header: t("Locale"), kind: "muted", size: 90 },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 130,
          labels: statusLabels,
          tones: {
            published: "success-light",
            scheduled: "info-light",
            archived: "warning-light",
          },
        },
        { key: "updatedAt", header: t("Updated"), kind: "muted", size: 130 },
      ]}
      facet={{ key: "status", label: t("Status"), values: statusLabels }}
      sorts={[
        { value: "updated", label: t("Recently updated") },
        { value: "published", label: t("Recently published") },
        { value: "title", label: t("Title") },
      ]}
      searchLabel={t("Search entries")}
      errorTitle={t("The content didn't load")}
      emptyIcon={<FileTextIcon />}
      emptyTitle={t("No entries found")}
      emptyDescription={t(
        "Pages and posts you write here are published to the public site when you say so.",
      )}
      emptyAction={canWrite ? <CreateEntryDialog /> : undefined}
    />
  );
}
