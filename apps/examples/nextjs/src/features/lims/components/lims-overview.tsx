import { FlaskConicalIcon, RulerIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import { BlockOverview } from "@/features/sales/components/block-overview";
import {
  dateFormatter,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { registerSample, saveMethod } from "../lims-actions";

export function LimsListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}

export async function sampleStatusLabels(): Promise<Record<string, string>> {
  const t = await getExtracted("lims");

  return {
    registered: t("Registered"),
    in_testing: t("In testing"),
    completed: t("Completed"),
    released: t("Released"),
    rejected: t("Rejected"),
  };
}

/** Samples, searched, filtered by status, sorted and paged on the server. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function SampleOverview({ query }: { query: RecordListUrlQuery }) {
  await requirePermission("lims.read");

  const [t, fmtDate, statuses] = await Promise.all([
    getExtracted("lims"),
    dateFormatter(),
    sampleStatusLabels(),
  ]);

  return (
    <BlockOverview
      pager={({ db }) => ({
        page: (options) => db.lims.samplePage(options),
        facets: (options) => db.lims.sampleFacets(options),
      })}
      map={{
        sorts: {
          received: { by: "receivedOn", direction: "desc" },
          oldest: { by: "receivedOn" },
          number: { by: "number" },
        },
        filters: { f: "status" },
        facets: { f: "status" },
      }}
      query={query}
      toRow={(sample) => ({
        id: sample.id,
        number: sample.number,
        title: sample.title,
        kind: sample.kind ?? null,
        lot: sample.lot ?? null,
        status: sample.status,
        receivedOn: fmtDate(sample.receivedOn.toString()),
      })}
      columns={[
        { key: "number", header: t("Number"), kind: "muted", size: 100 },
        {
          key: "title",
          header: t("Sample"),
          kind: "link",
          href: "/lims/{id}",
          size: 280,
        },
        { key: "kind", header: t("Kind"), kind: "muted", size: 130 },
        { key: "lot", header: t("Lot"), kind: "muted", size: 130 },
        { key: "receivedOn", header: t("Received"), kind: "muted", size: 130 },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 130,
          labels: statuses,
          tones: {
            in_testing: "info-light",
            completed: "warning-light",
            released: "success-light",
            rejected: "destructive-light",
          },
        },
      ]}
      facet={{ key: "status", label: t("Status"), values: statuses }}
      sorts={[
        { value: "received", label: t("Newest first") },
        { value: "oldest", label: t("Oldest first") },
        { value: "number", label: t("Number") },
      ]}
      searchLabel={t("Search samples")}
      errorTitle={t("The samples didn't load")}
      emptyIcon={<FlaskConicalIcon />}
      emptyTitle={t("No samples found")}
      emptyDescription={t(
        "Register a sample received for testing, or change the filters.",
      )}
    />
  );
}

/** The methods and their specification limits. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function MethodOverview({ query }: { query: RecordListUrlQuery }) {
  await requirePermission("lims.read");

  const t = await getExtracted("lims");

  return (
    <BlockOverview
      pager={({ db }) => ({
        page: (options) => db.lims.methodPage(options),
        facets: (options) => db.lims.methodFacets(options),
      })}
      map={{ sorts: { name: { by: "name" } } }}
      query={query}
      toRow={(method) => ({
        id: method.id,
        name: method.name,
        key: method.key,
        unit: method.unit ?? null,
        lower: method.lowerLimit ?? null,
        upper: method.upperLimit ?? null,
      })}
      columns={[
        { key: "name", header: t("Method"), kind: "text", size: 240 },
        { key: "key", header: t("Key"), kind: "muted", size: 160 },
        { key: "unit", header: t("Unit"), kind: "muted", size: 90 },
        { key: "lower", header: t("Lower limit"), kind: "number", size: 120 },
        { key: "upper", header: t("Upper limit"), kind: "number", size: 120 },
      ]}
      sorts={[{ value: "name", label: t("Name") }]}
      searchLabel={t("Search methods")}
      errorTitle={t("The methods didn't load")}
      emptyIcon={<RulerIcon />}
      emptyTitle={t("No methods yet")}
      emptyDescription={t(
        "A method names what is measured and the limits a result must stay within.",
      )}
    />
  );
}

// skeleton: renders from props and translations, so nothing of its own suspends
export async function RegisterSampleDialog() {
  const t = await getExtracted("lims");

  return (
    <ActionDialog
      action={registerSample}
      title={t("Register a sample")}
      description={t("The sample gets the next SMP number.")}
      trigger={t("Register sample")}
      submitLabel={t("Register")}
      successMessage={t("Sample registered")}
      redirectTo="/lims/{id}"
      fields={[
        { name: "title", label: t("Title"), kind: "text", required: true },
        { name: "kind", label: t("Kind"), kind: "text" },
        { name: "lot", label: t("Lot"), kind: "text" },
        { name: "receivedOn", label: t("Received on"), kind: "date" },
        { name: "notes", label: t("Notes"), kind: "textarea" },
      ]}
    />
  );
}

// skeleton: renders from props and translations, so nothing of its own suspends
export async function NewMethodDialog() {
  const t = await getExtracted("lims");

  return (
    <ActionDialog
      action={saveMethod}
      title={t("New method")}
      trigger={t("New method")}
      submitLabel={t("Save method")}
      successMessage={t("Method saved")}
      fields={[
        {
          name: "key",
          label: t("Key (lowercase letters, digits, underscores)"),
          kind: "text",
          required: true,
        },
        { name: "name", label: t("Name"), kind: "text", required: true },
        { name: "unit", label: t("Unit"), kind: "text" },
        { name: "lowerLimit", label: t("Lower limit"), kind: "text" },
        { name: "upperLimit", label: t("Upper limit"), kind: "text" },
      ]}
    />
  );
}
