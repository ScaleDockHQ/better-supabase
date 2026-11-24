import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { KpiBand } from "@/components/record-list/kpi-band";
import { Badge } from "@/components/reui/badge";
import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Link } from "@/i18n/navigation";

import { loadDefinitionDetail } from "../definition-detail/definition-detail-queries";
import { formatDuration, statusBadge } from "../workflow-labels";

/**
 * Render inside `<Suspense>`: reads the `definition` param, its versions and
 * runs.
 */
export async function DefinitionDetail({ id }: { id: string }) {
  const [detail, t, format] = await Promise.all([
    loadDefinitionDetail(id),
    getExtracted("workflows"),
    getFormatter(),
  ]);

  if (detail === null) {
    notFound();
  }

  const finished = detail.runs.filter(
    (run) =>
      run.status === "completed" ||
      run.status === "failed" ||
      run.status === "cancelled",
  );

  const completed = finished.filter((run) => run.status === "completed").length;
  const failed = detail.runs.filter((run) => run.status === "failed").length;

  const active = detail.runs.filter(
    (run) =>
      run.status === "queued" ||
      run.status === "running" ||
      run.status === "waiting",
  ).length;

  const successRate =
    finished.length === 0 ? 0 : Math.round((completed / finished.length) * 100);

  return (
    <RecordDetailFrame
      title={detail.name}
      description={detail.slug}
      status={
        <Badge
          variant={detail.published === null ? "secondary" : "success-light"}
        >
          {detail.published === null
            ? t("Not published")
            : t("Published v{version, number}", { version: detail.published })}
        </Badge>
      }
      actions={
        <Link
          href={`/workflows/builder/${detail.id}`}
          className={buttonVariants({ variant: "outline" })}
        >
          {t("Open in the builder")}
        </Link>
      }
      aside={
        <PropertiesRail
          title={t("Properties")}
          properties={[
            { label: t("Slug"), value: detail.slug },
            { label: t("Versions"), value: String(detail.versions.length) },
            {
              label: t("Updated"),
              value: format.dateTime(new Date(detail.updatedAt), {
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
          { label: t("Recent runs"), value: String(detail.runs.length) },
          { label: t("In progress"), value: String(active) },
          { label: t("Failed"), value: String(failed) },
          { label: t("Steps"), value: String(detail.steps.length) },
        ]}
      />
      <Card>
        <CardHeader>
          <CardTitle>{t("Progress")}</CardTitle>
          <CardDescription>
            {t("Share of the finished runs that completed.")}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <Progress value={successRate} aria-label={t("Completed runs")}>
            <span className="text-sm text-muted-foreground tabular-nums">
              {t("{completed, number} of {finished, number} finished runs", {
                completed,
                finished: finished.length,
              })}
            </span>
          </Progress>
          {detail.steps.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("Save a version in the builder to see its steps here.")}
            </p>
          ) : (
            <ol className="flex flex-col divide-y rounded-lg border text-sm">
              {detail.steps.map((step, index) => (
                <li key={step.id} className="flex items-center gap-3 px-3 py-2">
                  <span className="w-6 text-muted-foreground tabular-nums">
                    {index + 1}
                  </span>
                  <span className="font-medium">{step.label}</span>
                  <Badge variant="outline" className="ml-auto">
                    {step.kind}
                  </Badge>
                </li>
              ))}
            </ol>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Runs")}</CardTitle>
          <CardDescription>
            {t("The latest runs of this workflow, newest first.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {detail.runs.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("No runs yet. Run it from the builder.")}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Started")}</TableHead>
                  <TableHead>{t("Status")}</TableHead>
                  <TableHead className="text-right">{t("Duration")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {detail.runs.map((run) => (
                  <TableRow key={run.id}>
                    <TableCell>
                      <Link
                        href={`/workflows/runs/${run.id}`}
                        className="hover:underline"
                      >
                        {format.dateTime(new Date(run.createdAt), {
                          dateStyle: "medium",
                          timeStyle: "short",
                        })}
                      </Link>
                    </TableCell>
                    <TableCell>
                      <Badge variant={statusBadge(run.status)}>
                        {run.status}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {run.durationMs === null
                        ? "–"
                        : formatDuration(run.durationMs)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function DefinitionDetailSkeleton() {
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
