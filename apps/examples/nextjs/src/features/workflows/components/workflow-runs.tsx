"use client";

import { useWorkflowRuns } from "better-supabase/blocks/workflows/react";
import { WorkflowIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import { Badge } from "@/components/ui/badge";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
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

import { statusVariant, workflowName } from "../workflow-labels";

/**
 * The organization's runs from the workflows block, loaded again when a
 * run changes status (`workflow-runs:<tenant>`).
 */
export function WorkflowRuns({ tenant }: { tenant: string | null }) {
  const t = useExtracted("workflows");
  const format = useFormatter();
  const { runs, status } = useWorkflowRuns({
    tenant,
    schema: "api",
    limit: 50,
  });
  if (runs === undefined) return <WorkflowRunsSkeleton />;
  if (runs.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <WorkflowIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No runs yet")}</EmptyTitle>
          <EmptyDescription>
            {t("Start a sample workflow to see its run here.")}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }
  return (
    <div
      className="rounded-xl border"
      data-testid="workflow-runs"
      data-status={status}
    >
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t("Workflow")}</TableHead>
            <TableHead>{t("Status")}</TableHead>
            <TableHead className="text-right">{t("Started")}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {runs.map((run) => (
            <TableRow key={run.id}>
              <TableCell>
                <Link href={`/workflows/${run.id}`} className="font-medium">
                  {workflowName(run.definition)}
                </Link>
              </TableCell>
              <TableCell>
                <Badge variant={statusVariant(run.status)}>{run.status}</Badge>
              </TableCell>
              <TableCell className="text-muted-foreground text-right text-xs tabular-nums">
                {format.dateTime(new Date(run.createdAt.epochMilliseconds), {
                  dateStyle: "medium",
                  timeStyle: "short",
                })}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

export function WorkflowRunsSkeleton() {
  return (
    <div className="space-y-2" aria-busy="true">
      {Array.from({ length: 4 }, (_, index) => (
        <Skeleton key={index} className="h-11 w-full" />
      ))}
    </div>
  );
}
