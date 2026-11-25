import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { holds } from "@/features/sales/components/overview-support";

import { getControl } from "../compliance-queries";
import { AddEvidenceDialog } from "./add-evidence-dialog";
import { ControlStatusBadge } from "./control-status-badge";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>`: one control, the evidence that decides its status
 * and the recurring tasks that collect it.
 */
export async function ControlDetail({ controlId }: { controlId: string }) {
  const [state, t, canCollect] = await Promise.all([
    getControl(controlId),
    getExtracted("compliance"),
    holds("compliance.collect"),
  ]);

  if (state.kind === "no-organization") {
    notFound();
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The control didn't load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={retry}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  const control = state.data;
  const canAdd = canCollect && control.status !== "not_applicable";

  return (
    <RecordDetailFrame
      title={`${control.code} ${control.title}`}
      description={control.description ?? undefined}
      status={<ControlStatusBadge status={control.status} />}
      actions={canAdd ? <AddEvidenceDialog controlId={control.id} /> : null}
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Details")}</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-2 gap-2 text-sm">
            <span className="text-muted-foreground">{t("Source")}</span>
            <span className="text-right">{control.source ?? "-"}</span>
            <span className="text-muted-foreground">{t("Jurisdiction")}</span>
            <span className="text-right">{control.jurisdiction ?? "-"}</span>
            <span className="text-muted-foreground">{t("Evidence")}</span>
            <span className="text-right tabular-nums">
              {control.evidence.length}
            </span>
          </CardContent>
        </Card>
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Evidence tasks")}</CardTitle>
          <CardDescription>
            {t("An overdue task fails the control until evidence answers it.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {control.tasks.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("No task collects evidence for this control.")}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Task")}</TableHead>
                  <TableHead>{t("Every")}</TableHead>
                  <TableHead>{t("Due")}</TableHead>
                  <TableHead>
                    <span className="sr-only">{t("Actions")}</span>
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {control.tasks.map((task) => (
                  <TableRow key={task.id}>
                    <TableCell className="font-medium">{task.title}</TableCell>
                    <TableCell className="tabular-nums">
                      {t("{days, plural, one {# day} other {# days}}", {
                        days: task.intervalDays,
                      })}
                    </TableCell>
                    <TableCell>
                      <span className="flex items-center gap-2 tabular-nums">
                        {task.dueOn}
                        {task.overdue ? (
                          <Badge variant="destructive-light">
                            {t("Overdue")}
                          </Badge>
                        ) : null}
                      </span>
                    </TableCell>
                    <TableCell className="text-right">
                      {canAdd ? (
                        <AddEvidenceDialog
                          controlId={control.id}
                          task={{ id: task.id, title: task.title }}
                        />
                      ) : null}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Evidence")}</CardTitle>
          <CardDescription>
            {t("Valid evidence passes the control; expired evidence fails it.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {control.evidence.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("No evidence yet.")}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Note")}</TableHead>
                  <TableHead>{t("Collected")}</TableHead>
                  <TableHead>{t("Valid until")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {control.evidence.map((item) => (
                  <TableRow key={item.id}>
                    <TableCell>{item.note ?? t("Attachment")}</TableCell>
                    <TableCell className="tabular-nums">
                      {item.collectedAt.slice(0, 10)}
                    </TableCell>
                    <TableCell>
                      <span className="flex items-center gap-2 tabular-nums">
                        {item.validUntil ?? t("No end")}
                        {item.valid ? null : (
                          <Badge variant="destructive-light">
                            {t("Expired")}
                          </Badge>
                        )}
                      </span>
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

export function ControlDetailSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <RecordSectionSkeleton rows={3} />
        <RecordSectionSkeleton rows={2} />
      </div>
      <RecordSectionSkeleton rows={3} />
    </div>
  );
}
