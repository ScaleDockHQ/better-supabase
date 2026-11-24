import {
  BriefcaseIcon,
  CircleCheckIcon,
  UserPlusIcon,
  UsersIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { BlockListView } from "@/components/record-list/block-list-view";
import { KpiBand } from "@/components/record-list/kpi-band";
import {
  dateFormatter,
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { loadApplications, settle } from "../people-queries";
import { PeopleLoadError } from "./people-load-error";

/** The figures above the application table. */
// skeleton: the page's Suspense fallback is KpiBandSkeleton
export async function HiringKpis() {
  await requirePermission("hiring.read");

  const [t, applications] = await Promise.all([
    getExtracted("people"),
    settle(loadApplications),
  ]);

  if (applications.kind === "no-organization") {
    return null;
  }

  if (applications.kind === "error") {
    return <PeopleLoadError title={t("The applications didn't load")} />;
  }

  const { rows } = applications.data;

  const count = (state: string) =>
    rows.filter((row) => row.state === state).length;

  return (
    <KpiBand
      kpis={[
        {
          label: t("Open applications"),
          hint: t("Still moving through the pipeline"),
          value: String(count("active")),
          icon: <UsersIcon className="size-4" />,
        },
        {
          label: t("Openings"),
          hint: t("With at least one application"),
          value: String(new Set(rows.map((row) => row.jobId)).size),
          icon: <BriefcaseIcon className="size-4" />,
        },
        {
          label: t("Hired"),
          value: String(count("hired")),
          icon: <CircleCheckIcon className="size-4" />,
        },
        {
          label: t("Rejected"),
          value: String(count("rejected") + count("withdrawn")),
          icon: <UserPlusIcon className="size-4" />,
        },
      ]}
    />
  );
}

/** Every application as a table, filtered by state. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ApplicationOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("hiring.read");

  const [t, applications, fmtDate, canWrite] = await Promise.all([
    getExtracted("people"),
    settle(loadApplications),
    dateFormatter(),
    holds("hiring.write"),
  ]);

  if (applications.kind === "no-organization") {
    return null;
  }

  if (applications.kind === "error") {
    return <PeopleLoadError title={t("The applications didn't load")} />;
  }

  const states = {
    active: t("Active"),
    hired: t("Hired"),
    rejected: t("Rejected"),
    withdrawn: t("Withdrawn"),
  };

  const selected = query.facets["f"]?.[0];

  const counts = Object.fromEntries(
    Object.keys(states).map((state) => [
      state,
      applications.data.rows.filter((row) => row.state === state).length,
    ]),
  );

  const rows = applications.data.rows
    .filter((row) => selected === undefined || row.state === selected)
    .map((row) => ({
      id: row.id,
      candidate: row.candidateName,
      opening: row.jobTitle,
      stage: row.stageName,
      state: row.state,
      source: row.source,
      applied: fmtDate(row.createdAt),
    }));

  return (
    <BlockListView
      rows={rows}
      columns={[
        {
          key: "candidate",
          header: t("Candidate"),
          kind: "link",
          href: "/people/hiring/{id}",
          size: 220,
        },
        { key: "opening", header: t("Opening"), kind: "text", size: 220 },
        { key: "stage", header: t("Stage"), kind: "muted", size: 150 },
        {
          key: "state",
          header: t("State"),
          kind: "badge",
          size: 120,
          labels: states,
          tones: {
            active: "info-light",
            hired: "success-light",
            rejected: "destructive-light",
            withdrawn: "secondary",
          },
        },
        { key: "source", header: t("Source"), kind: "muted", size: 120 },
        { key: "applied", header: t("Applied"), kind: "muted", size: 130 },
      ]}
      facetKey="f"
      facetLabel={t("State")}
      facetOptions={Object.entries(states)
        .map(([value, label]) => ({ value, label, count: counts[value] ?? 0 }))
        .filter((option) => option.count > 0 || option.value === selected)}
      sorts={[]}
      nextCursor={null}
      emptyIcon={<UsersIcon />}
      emptyTitle={t("No applications yet")}
      emptyDescription={
        canWrite
          ? t("Add a candidate to an opening on the board.")
          : t("Applications appear here as candidates apply.")
      }
    />
  );
}
