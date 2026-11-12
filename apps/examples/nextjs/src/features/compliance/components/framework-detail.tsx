import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";
import { notFound } from "next/navigation";

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
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

import type { ControlRow } from "../compliance-queries";

import { getFramework } from "../compliance-queries";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

const STATUS_VARIANT: Record<
  ControlRow["status"],
  "destructive-light" | "secondary" | "success-light"
> = {
  passing: "success-light",
  failing: "destructive-light",
  not_started: "secondary",
  not_applicable: "secondary",
};

/** Render inside `<Suspense>`: one framework and the status of each control. */
export async function FrameworkDetail({
  frameworkId,
}: {
  frameworkId: string;
}) {
  const [state, t] = await Promise.all([
    getFramework(frameworkId),
    getExtracted("compliance"),
  ]);

  if (state.kind === "no-organization") {
    notFound();
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The framework didn't load")}</AlertTitle>
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

  const { name, version, controls } = state.data;

  const statusLabels: Record<ControlRow["status"], string> = {
    passing: t("Passing"),
    failing: t("Failing"),
    not_started: t("Not started"),
    not_applicable: t("Not applicable"),
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>{name}</CardTitle>
        <CardDescription>
          {version
            ? t("Version {version}, {count, number} controls", {
                version,
                count: controls.length,
              })
            : t("{count, number} controls", { count: controls.length })}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {controls.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("This framework has no controls yet.")}
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Code")}</TableHead>
                <TableHead>{t("Control")}</TableHead>
                <TableHead>{t("Source")}</TableHead>
                <TableHead>{t("Status")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {controls.map((control) => (
                <TableRow key={control.id}>
                  <TableCell className="font-mono text-xs">
                    {control.code}
                  </TableCell>
                  <TableCell className="font-medium">{control.title}</TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {control.source ?? "-"}
                    {control.jurisdiction ? ` (${control.jurisdiction})` : ""}
                  </TableCell>
                  <TableCell>
                    <Badge variant={STATUS_VARIANT[control.status]}>
                      {statusLabels[control.status]}
                    </Badge>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

export function FrameworkDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}
