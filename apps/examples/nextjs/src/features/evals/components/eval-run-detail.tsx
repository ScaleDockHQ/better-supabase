import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { KpiBand } from "@/components/record-list/kpi-band";
import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";

import type { EvalParams } from "../evals-search-params";

import { getEvalWorkspace } from "../evals-queries";
import { EvalResults } from "./eval-results";

/**
 * Render inside `<Suspense>`: reads the `name` and `run` params. One run of the
 * dataset with its scores, its comparison with the run before and its results.
 */
export async function EvalRunDetail({
  name,
  runId,
  filters,
}: {
  name: string;
  runId: string;
  filters: Promise<EvalParams>;
}) {
  const [workspace, t, format, params] = await Promise.all([
    filters.then((resolved) =>
      getEvalWorkspace(name, { ...resolved, run: runId }),
    ),
    getExtracted("evals"),
    getFormatter(),
    filters,
  ]);

  const run = workspace?.selected;

  if (workspace === undefined || run === undefined || run.id !== runId) {
    notFound();
  }

  const summary = run.summary;

  return (
    <RecordDetailFrame
      title={`${name} v${run.promptVersion}`}
      description={run.model}
      status={
        <Badge
          variant={
            run.status === "completed"
              ? "success-light"
              : run.status === "failed"
                ? "destructive-light"
                : "info-light"
          }
        >
          {run.status === "completed"
            ? t("Completed")
            : run.status === "failed"
              ? t("Failed")
              : run.status === "cancelled"
                ? t("Cancelled")
                : t("Running")}
        </Badge>
      }
      aside={
        <PropertiesRail
          title={t("Properties")}
          properties={[
            { label: t("Prompt version"), value: `v${run.promptVersion}` },
            { label: t("Model"), value: run.model },
            {
              label: t("Started"),
              value: format.dateTime(new Date(run.createdAt), {
                dateStyle: "medium",
                timeStyle: "short",
              }),
            },
          ]}
        />
      }
    >
      <KpiBand
        kpis={[
          {
            label: t("Pass rate"),
            value:
              summary === undefined
                ? "–"
                : format.number(summary.passRate, { style: "percent" }),
          },
          {
            label: t("Passed"),
            value: summary === undefined ? "–" : String(summary.passed),
          },
          {
            label: t("Failed"),
            value: summary === undefined ? "–" : String(summary.failed),
          },
          {
            label: t("Errored"),
            value: summary === undefined ? "–" : String(summary.errored),
          },
        ]}
      />
      <EvalResults
        results={workspace.results}
        comparison={workspace.comparison}
        failedOnly={params.failed}
      />
    </RecordDetailFrame>
  );
}

export function EvalRunDetailSkeleton() {
  return (
    <div className="grid items-start gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-4 lg:col-span-2">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-64 w-full" />
      </div>
      <Skeleton className="h-48 w-full" />
    </div>
  );
}
