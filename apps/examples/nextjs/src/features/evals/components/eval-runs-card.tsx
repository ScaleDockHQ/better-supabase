"use client";

import { useExtracted, useFormatter } from "next-intl";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Link } from "@/i18n/navigation";

import type { EvalRunRow } from "../evals-queries";

import { PassRateChartLazy } from "./pass-rate-chart-lazy";

/** The runs of the dataset, newest first, with the pass-rate trend over them. */
export function EvalRunsCard({
  name,
  runs,
  selectedId,
}: {
  name: string;
  runs: readonly EvalRunRow[];
  selectedId: string | undefined;
}) {
  const t = useExtracted("evals");
  const format = useFormatter();

  const points = runs
    .filter((run) => run.summary !== undefined)
    .toReversed()
    .map((run) => ({
      label: `v${run.promptVersion}`,
      passRate: Math.round((run.summary?.passRate ?? 0) * 100),
    }));

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Runs")}</CardTitle>
        <CardDescription>
          {t(
            "Pass rate per run, oldest first. Pick a run to read its results.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {points.length > 0 ? <PassRateChartLazy points={points} /> : null}
        <ul className="divide-y rounded-lg border text-sm">
          {runs.map((run) => (
            <li key={run.id}>
              <Link
                href={`/assistant/evals/${encodeURIComponent(name)}?run=${run.id}`}
                aria-current={run.id === selectedId ? "true" : undefined}
                className="flex flex-wrap items-center gap-2 px-3 py-2 transition-colors hover:bg-muted aria-[current=true]:bg-muted"
              >
                <span className="font-medium tabular-nums">
                  v{run.promptVersion}
                </span>
                <span className="text-muted-foreground">{run.model}</span>
                <span className="ml-auto flex items-center gap-2">
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
                  <span className="w-12 text-right tabular-nums">
                    {run.summary === undefined
                      ? "–"
                      : format.number(run.summary.passRate, {
                          style: "percent",
                        })}
                  </span>
                  <span className="text-xs text-muted-foreground tabular-nums">
                    {format.dateTime(new Date(run.createdAt), {
                      dateStyle: "medium",
                      timeStyle: "short",
                    })}
                  </span>
                </span>
              </Link>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
