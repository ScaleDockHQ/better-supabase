import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { ActionButton } from "@/features/sales/components/action-button";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import {
  DetailTable,
  FactGrid,
} from "@/features/sales/components/detail-table";
import {
  dateFormatter,
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";
import { Link } from "@/i18n/navigation";

import { completeSample, decideSample, recordResult } from "../lims-actions";
import { loadInstruments, loadMethods, loadSample } from "../lims-queries";
import { sampleStatusLabels } from "./lims-overview";

/** The specification limits of a method as text. */
function limitsOf(
  method: { lowerLimit: number | null; upperLimit: number | null } | undefined,
): string {
  if (
    method === undefined ||
    (method.lowerLimit === null && method.upperLimit === null)
  ) {
    return "–";
  }

  return `${method.lowerLimit ?? "–"} to ${method.upperLimit ?? "–"}`;
}

export function SampleDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

const TONE = new Map<
  string,
  | "info-light"
  | "warning-light"
  | "success-light"
  | "destructive-light"
  | "secondary"
>([
  ["in_testing", "info-light"],
  ["completed", "warning-light"],
  ["released", "success-light"],
  ["rejected", "destructive-light"],
]);

/**
 * A sample with its test results, its nonconformities and the steps to release
 * it.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function SampleDetail({ id, tab }: { id: string; tab: string }) {
  await requirePermission("lims.read");

  const [
    t,
    loaded,
    methodsLoaded,
    instrumentsLoaded,
    fmtDate,
    statuses,
    canWrite,
    canManage,
  ] = await Promise.all([
    getExtracted("lims"),
    settle(() => loadSample(id)),
    settle(loadMethods),
    settle(loadInstruments),
    dateFormatter(),
    sampleStatusLabels(),
    holds("lims.write"),
    holds("lims.manage"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The sample didn't load")} />;
  }

  const sample = loaded.data;

  if (!sample) {
    notFound();
  }

  const methods = methodsLoaded.kind === "ok" ? methodsLoaded.data : [];

  const instruments =
    instrumentsLoaded.kind === "ok" ? instrumentsLoaded.data : [];

  const methodOf = new Map(methods.map((method) => [method.id, method]));

  const active =
    sample.status === "registered" || sample.status === "in_testing";

  const nonconformities = sample.results.filter((row) => row.caseId !== null);

  const resultRows = (rows: typeof sample.results) =>
    rows.map((row) => {
      const method = methodOf.get(row.methodId);

      return {
        key: row.id,
        cells: [
          method?.name ?? row.methodId.slice(0, 8),
          `${row.value}${method?.unit ? ` ${method.unit}` : ""}`,
          limitsOf(method),
          <Badge
            key="outcome"
            variant={
              row.outcome === "in_spec" ? "success-light" : "destructive-light"
            }
          >
            {row.outcome === "in_spec"
              ? t("In specification")
              : t("Out of specification")}
          </Badge>,
          fmtDate(row.testedAt),
        ],
      };
    });

  return (
    <RecordDetailFrame
      title={sample.title}
      description={sample.number}
      status={
        <Badge variant={TONE.get(sample.status) ?? "secondary"}>
          {statuses[sample.status]}
        </Badge>
      }
      actions={
        <>
          {canWrite && active && sample.results.length > 0 ? (
            <ActionButton
              action={completeSample}
              input={{ sampleId: sample.id }}
              label={t("Complete testing")}
              successMessage={t("Sample completed")}
              variant="default"
            />
          ) : null}
          {canManage && sample.status === "completed" ? (
            <ActionButton
              action={decideSample}
              input={{ sampleId: sample.id, action: "release" }}
              label={t("Release")}
              successMessage={t("Sample released")}
              variant="default"
            />
          ) : null}
          {canManage &&
          sample.status !== "released" &&
          sample.status !== "rejected" ? (
            <ActionDialog
              action={decideSample}
              title={t("Reject sample")}
              trigger={t("Reject")}
              submitLabel={t("Reject sample")}
              successMessage={t("Sample rejected")}
              variant="outline"
              hidden={{ sampleId: sample.id, action: "reject" }}
              fields={[
                {
                  name: "reason",
                  label: t("Reason"),
                  kind: "textarea",
                  required: true,
                },
              ]}
            />
          ) : null}
        </>
      }
    >
      <RecordDetailTabs
        base={`/lims/${id}`}
        active={tab}
        tabs={[
          { value: "results", label: t("Tests") },
          { value: "nonconformities", label: t("Nonconformities") },
          { value: "details", label: t("Details") },
        ]}
      />
      {tab === "nonconformities" ? (
        <DetailTable
          title={t("Nonconformities")}
          description={t(
            "A result outside the method's limits opens a nonconformity case automatically.",
          )}
          head={[
            t("Method"),
            t("Result"),
            t("Limits"),
            t("Outcome"),
            t("Case"),
          ]}
          rows={resultRows(nonconformities).map((row, index) => ({
            ...row,
            cells: [
              ...row.cells.slice(0, 4),
              <Link
                key="case"
                href="/cases"
                className="font-medium hover:underline"
              >
                {(nonconformities[index]?.caseId ?? "").slice(0, 8)}
              </Link>,
            ],
          }))}
          emptyTitle={t("No nonconformities")}
          emptyDescription={t("Every result so far is inside its limits.")}
        />
      ) : tab === "details" ? (
        <FactGrid
          facts={[
            { label: t("Kind"), value: sample.kind ?? "–" },
            { label: t("Lot"), value: sample.lot ?? "–" },
            { label: t("Received"), value: fmtDate(sample.receivedOn) },
            { label: t("Completed"), value: fmtDate(sample.completedAt) },
            { label: t("Released"), value: fmtDate(sample.releasedAt) },
            {
              label: t("Notes"),
              value: sample.rejectionReason ?? sample.notes ?? "–",
            },
          ]}
        />
      ) : (
        <DetailTable
          title={t("Tests")}
          description={t(
            "Each result is checked against the limits of its method.",
          )}
          action={
            canWrite &&
            active &&
            methods.length > 0 &&
            instruments.length > 0 ? (
              <ActionDialog
                action={recordResult}
                title={t("Record a result")}
                trigger={t("Record result")}
                submitLabel={t("Record")}
                successMessage={t("Result recorded")}
                variant="outline"
                hidden={{ sampleId: sample.id }}
                fields={[
                  {
                    name: "methodId",
                    label: t("Method"),
                    kind: "select",
                    options: methods.map((method) => ({
                      value: method.id,
                      label: method.name,
                    })),
                  },
                  {
                    name: "instrumentId",
                    label: t("Instrument (needs a valid calibration)"),
                    kind: "select",
                    options: instruments.map((instrument) => ({
                      value: instrument.id,
                      label: instrument.name,
                    })),
                  },
                  {
                    name: "value",
                    label: t("Value"),
                    kind: "text",
                    required: true,
                  },
                  { name: "note", label: t("Note"), kind: "text" },
                ]}
              />
            ) : undefined
          }
          head={[
            t("Method"),
            t("Result"),
            t("Limits"),
            t("Outcome"),
            t("Tested"),
          ]}
          rows={resultRows(sample.results)}
          emptyTitle={t("No results yet")}
          emptyDescription={t("Record a result for a method to start testing.")}
        />
      )}
    </RecordDetailFrame>
  );
}
