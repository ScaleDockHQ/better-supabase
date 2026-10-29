import type { QualificationStatus } from "better-supabase/blocks/qualifications";

import { IdCardIcon, TriangleAlertIcon } from "lucide-react";
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
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";

import { getMyQualifications } from "../qualifications-queries";

// #region recipe:my-qualifications
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

const STATUS_VARIANT = {
  valid: "success-light",
  expiring: "warning-light",
  expired: "destructive-light",
  revoked: "secondary",
} as const satisfies Record<QualificationStatus, string>;

/**
 * Render inside `<Suspense>`: the signed-in member's certificates and licences
 * with their expiry, then the required ones they still lack. Needs no
 * permission; members read their own holdings and gaps.
 */
export async function MyQualifications() {
  const [state, t, format] = await Promise.all([
    getMyQualifications(),
    getExtracted("qualifications"),
    getFormatter(),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="my-qualifications">
        <TriangleAlertIcon />
        <AlertTitle>{t("Your qualifications didn't load")}</AlertTitle>
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

  const { holdings, gaps } = state.data;

  const label = (status: QualificationStatus) => {
    switch (status) {
      case "valid": {
        return t("Valid");
      }

      case "expiring": {
        return t("Expiring");
      }

      case "expired": {
        return t("Expired");
      }

      case "revoked": {
        return t("Revoked");
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
    <Card data-recipe="my-qualifications">
      <CardHeader>
        <CardTitle>{t("My qualifications")}</CardTitle>
        <CardDescription>
          {t(
            "The certificates and licences you hold, and the ones your role still requires.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {holdings.length === 0 && gaps.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <IdCardIcon />
              </EmptyMedia>
              <EmptyTitle>{t("Nothing to show yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Qualifications appear here once an admin grants one or you complete a course that awards one.",
                )}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : null}
        {holdings.length > 0 ? (
          <ul className="flex flex-col gap-2">
            {holdings.map((holding) => (
              <li
                key={holding.id}
                className="flex flex-wrap items-center justify-between gap-2"
              >
                <div className="flex flex-col gap-1">
                  <span className="text-sm font-medium">
                    {holding.typeName}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {holding.expiresOn
                      ? t("Expires {date}", { date: day(holding.expiresOn) })
                      : t("Never expires")}
                  </span>
                </div>
                <Badge variant={STATUS_VARIANT[holding.status]}>
                  {label(holding.status)}
                </Badge>
              </li>
            ))}
          </ul>
        ) : null}
        {gaps.length > 0 ? (
          <div className="flex flex-col gap-2">
            <span className="text-sm font-medium">{t("Still required")}</span>
            <div className="flex flex-wrap gap-2">
              {gaps.map((gap) => (
                <Badge key={gap.key} variant="destructive-light">
                  {gap.typeName}
                </Badge>
              ))}
            </div>
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}

export function MyQualificationsSkeleton() {
  return <Skeleton className="h-48" aria-busy="true" />;
}
// #endregion recipe:my-qualifications
