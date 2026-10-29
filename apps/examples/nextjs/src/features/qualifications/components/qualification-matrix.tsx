import type { QualificationGapStatus } from "better-supabase/blocks/qualifications";

import { BadgeCheckIcon, TriangleAlertIcon } from "lucide-react";
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
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

import { getMatrix } from "../qualifications-queries";

// #region recipe:qualification-matrix
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

const GAP_VARIANT = {
  missing: "destructive-light",
  expired: "destructive-light",
  expiring: "warning-light",
} as const satisfies Record<QualificationGapStatus, string>;

/**
 * Render inside `<Suspense>` for members with `qualifications.read`: each
 * required qualification a member lacks, has let lapse or is about to lose.
 */
export async function QualificationMatrix() {
  const [state, t, format] = await Promise.all([
    getMatrix(),
    getExtracted("qualifications"),
    getFormatter(),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="qualification-matrix">
        <TriangleAlertIcon />
        <AlertTitle>{t("The qualification gaps didn't load")}</AlertTitle>
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

  const { types, gaps } = state.data;

  if (types === 0) {
    return (
      <Empty className="border" data-recipe="qualification-matrix">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <BadgeCheckIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No qualifications yet")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Add a qualification type such as a forklift licence, then name the roles or teams that must hold it.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <a
            className="text-sm underline underline-offset-4"
            href="https://bettersupabase.com/docs/blocks/qualifications"
          >
            {t("Read the qualifications guide")}
          </a>
        </EmptyContent>
      </Empty>
    );
  }

  const label = (status: QualificationGapStatus) => {
    switch (status) {
      case "missing": {
        return t("Missing");
      }

      case "expired": {
        return t("Expired");
      }

      case "expiring": {
        return t("Expiring");
      }

      default: {
        const unknown: never = status;

        return unknown;
      }
    }
  };

  const day = (date: string) =>
    format.dateTime(new Date(date), { dateStyle: "medium", timeZone: "UTC" });

  return (
    <Card data-recipe="qualification-matrix">
      <CardHeader>
        <CardTitle>{t("Qualification gaps")}</CardTitle>
        <CardDescription>
          {t(
            "Members who lack a required qualification, hold an expired one or will lose one soon.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {gaps.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("Every member holds the qualifications their role requires.")}
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Member")}</TableHead>
                <TableHead>{t("Qualification")}</TableHead>
                <TableHead>{t("Status")}</TableHead>
                <TableHead>{t("Expires")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {gaps.map((gap) => (
                <TableRow key={gap.key}>
                  <TableCell className="font-medium">
                    {gap.holderTitle}
                  </TableCell>
                  <TableCell>{gap.typeName}</TableCell>
                  <TableCell>
                    <Badge variant={GAP_VARIANT[gap.status]}>
                      {label(gap.status)}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {gap.expiresOn ? day(gap.expiresOn) : "–"}
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

export function QualificationMatrixSkeleton() {
  return <Skeleton className="h-64" aria-busy="true" />;
}
// #endregion recipe:qualification-matrix
