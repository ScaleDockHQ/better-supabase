import { SendIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { BlockOverview } from "@/features/sales/components/block-overview";
import {
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { SampleSequenceButton } from "./sequence-controls";

/**
 * The organization's sequences, searched, filtered by status and paged on the
 * server.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function SequenceOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("sequences.read");

  const [t, manage] = await Promise.all([
    getExtracted("sequences"),
    holds("sequences.manage"),
  ]);

  const statuses = {
    draft: t("Draft"),
    active: t("Active"),
    paused: t("Paused"),
    archived: t("Archived"),
  };

  return (
    <BlockOverview
      pager={({ db }) => ({
        page: (options) => db.sequences.sequencePage(options),
        facets: (options) => db.sequences.sequenceFacets(options),
      })}
      map={{
        sorts: {
          name: { by: "name" },
          updated: { by: "updatedAt", direction: "desc" },
        },
        filters: { f: "status" },
        facets: { f: "status" },
      }}
      query={query}
      toRow={(sequence) => ({
        id: sequence.id,
        name: sequence.name,
        status: sequence.status,
        steps: sequence.steps.length,
        active: sequence.counts.active,
        completed: sequence.counts.completed,
        replied: sequence.counts.replied,
      })}
      columns={[
        {
          key: "name",
          header: t("Sequence"),
          kind: "link",
          href: "/crm/sequences/{id}",
          size: 280,
        },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 130,
          labels: statuses,
          tones: {
            draft: "secondary",
            active: "success-light",
            paused: "warning-light",
          },
        },
        { key: "steps", header: t("Steps"), kind: "number", size: 90 },
        { key: "active", header: t("Active"), kind: "number", size: 100 },
        { key: "completed", header: t("Completed"), kind: "number", size: 110 },
        { key: "replied", header: t("Replied"), kind: "number", size: 100 },
      ]}
      facet={{ key: "status", label: t("Status"), values: statuses }}
      sorts={[
        { value: "name", label: t("Name") },
        { value: "updated", label: t("Recently updated") },
      ]}
      errorTitle={t("The sequences didn't load")}
      emptyIcon={<SendIcon />}
      emptyTitle={t("No sequences yet")}
      emptyDescription={
        manage
          ? t("Create a sample sequence, then activate it to enroll contacts.")
          : t("An admin sets up the sequences your team enrolls contacts in.")
      }
      emptyAction={manage ? <SampleSequenceButton /> : undefined}
    />
  );
}
