import { ShieldCheckIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";

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
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
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

import { getPosture } from "../compliance-queries";

// #region recipe:control-posture
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>`: one card per compliance framework with how many
 * of its controls pass, then the evidence tasks that are past their due date.
 */
export async function ControlPosture() {
  const [state, t, format] = await Promise.all([
    getPosture(),
    getExtracted("compliance"),
    getFormatter(),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="control-posture">
        <TriangleAlertIcon />
        <AlertTitle>{t("The control posture didn't load")}</AlertTitle>
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

  const { frameworks, overdue } = state.data;

  if (frameworks.length === 0) {
    return (
      <Empty className="border" data-recipe="control-posture">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <ShieldCheckIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No frameworks yet")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Add a framework such as SOC 2 or ISO 27001 with the controls block, then link evidence to each control.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <a
            className="text-sm underline underline-offset-4"
            href="https://bettersupabase.com/docs/blocks/compliance"
          >
            {t("Read the controls guide")}
          </a>
        </EmptyContent>
      </Empty>
    );
  }

  const day = (date: string) =>
    format.dateTime(new Date(date), { dateStyle: "medium", timeZone: "UTC" });

  return (
    <div className="flex flex-col gap-6" data-recipe="control-posture">
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {frameworks.map((framework) => {
          const applicable = framework.total - framework.notApplicable;

          const percent =
            applicable === 0
              ? 100
              : Math.round((framework.passing / applicable) * 100);

          return (
            <Card key={framework.frameworkId}>
              <CardHeader>
                <CardTitle>{framework.name}</CardTitle>
                <CardDescription>
                  {t(
                    "{passing, number} of {applicable, number} controls passing",
                    { passing: framework.passing, applicable },
                  )}
                </CardDescription>
              </CardHeader>
              <CardContent className="flex flex-col gap-3">
                <Progress value={percent} aria-label={t("Controls passing")} />
                <div className="flex flex-wrap gap-2">
                  <Badge variant="success-light">
                    {t("{count, number} passing", { count: framework.passing })}
                  </Badge>
                  {framework.failing > 0 ? (
                    <Badge variant="destructive-light">
                      {t("{count, number} failing", {
                        count: framework.failing,
                      })}
                    </Badge>
                  ) : null}
                  {framework.notStarted > 0 ? (
                    <Badge variant="secondary">
                      {t("{count, number} not started", {
                        count: framework.notStarted,
                      })}
                    </Badge>
                  ) : null}
                  {framework.overdueTasks > 0 ? (
                    <Badge variant="warning-light">
                      {t("{count, number} overdue tasks", {
                        count: framework.overdueTasks,
                      })}
                    </Badge>
                  ) : null}
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>
      <Card>
        <CardHeader>
          <CardTitle>{t("Overdue evidence")}</CardTitle>
          <CardDescription>
            {t(
              "Recurring tasks whose evidence is past due. Collecting evidence moves the task to its next due date.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {overdue.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("Every evidence task is on schedule.")}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Task")}</TableHead>
                  <TableHead>{t("Control")}</TableHead>
                  <TableHead>{t("Due")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {overdue.map((task) => (
                  <TableRow key={task.id}>
                    <TableCell className="font-medium">{task.title}</TableCell>
                    <TableCell className="font-mono text-xs">
                      {task.controlCode ?? "–"}
                    </TableCell>
                    <TableCell>
                      <Badge variant="destructive-light">
                        {day(task.dueOn)}
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

export function ControlPostureSkeleton() {
  return (
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3" aria-busy="true">
      <Skeleton className="h-36 rounded-xl" />
      <Skeleton className="h-36 rounded-xl" />
      <Skeleton className="h-36 rounded-xl" />
    </div>
  );
}
// #endregion recipe:control-posture
