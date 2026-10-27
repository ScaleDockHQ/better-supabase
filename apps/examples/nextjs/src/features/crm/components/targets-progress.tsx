import { formatMoney, money } from "better-supabase/commerce";
import { TargetIcon } from "lucide-react";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";
import { Temporal } from "temporal-polyfill";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardAction,
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
import { Progress, ProgressLabel } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import type { TargetRow } from "../crm-queries";

import { loadTargets, settle } from "../crm-queries";
import { CreateTargetDialog } from "./create-target-dialog";
import { CrmLoadError } from "./crm-load-error";

// #region recipe:targets-progress
/**
 * Render inside `<Suspense>`: the targets running today and how far along they
 * are.
 */
export async function TargetsProgress() {
  const [t, format, locale, permissions] = await Promise.all([
    getExtracted("crm"),
    getFormatter(),
    getLocale(),
    getPermissions(),
  ]);

  if (!can(permissions, "targets.read")) {
    return null;
  }

  const targets = await settle(loadTargets);

  if (targets.kind === "no-organization") {
    return null;
  }

  const canManage = can(permissions, "targets.manage");

  const amountOf = (target: TargetRow, value: bigint) =>
    target.currency === null
      ? format.number(value)
      : formatMoney(money(value, target.currency), locale);

  return (
    <Card data-recipe="targets-progress">
      <CardHeader>
        <CardTitle>{t("Targets")}</CardTitle>
        <CardDescription>
          {t("Won deals against this period's goals.")}
        </CardDescription>
        {canManage && targets.kind === "ok" && targets.data.length > 0 ? (
          <CardAction>
            <CreateTargetDialog variant="outline" />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {targets.kind === "error" ? (
          <CrmLoadError title={t("The targets didn't load")} />
        ) : targets.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <TargetIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No targets running")}</EmptyTitle>
              <EmptyDescription>
                {canManage
                  ? t("Set a goal for the amount or number of deals won.")
                  : t("An admin sets the sales targets.")}
              </EmptyDescription>
            </EmptyHeader>
            {canManage ? (
              <EmptyContent>
                <CreateTargetDialog />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <ul className="grid gap-6 md:grid-cols-2">
            {targets.data.map((target) => (
              <li key={target.id} className="flex flex-col gap-2">
                <Progress
                  value={Math.min(target.attainment * 100, 100)}
                  aria-label={target.name}
                >
                  <ProgressLabel>{target.name}</ProgressLabel>
                  {target.attainment >= 1 ? (
                    <Badge variant="success-light" className="ml-auto">
                      {t("Reached")}
                    </Badge>
                  ) : (
                    <span className="ml-auto text-sm text-muted-foreground tabular-nums">
                      {format.number(target.attainment, {
                        style: "percent",
                        maximumFractionDigits: 0,
                      })}
                    </span>
                  )}
                </Progress>
                <span className="text-xs text-muted-foreground tabular-nums">
                  {t("{progress} of {goal}, {start} to {end}", {
                    progress: amountOf(target, target.progress),
                    goal: amountOf(target, target.goal),
                    start: Temporal.PlainDate.from(
                      target.periodStart,
                    ).toLocaleString(locale, { dateStyle: "medium" }),
                    end: Temporal.PlainDate.from(
                      target.periodEnd,
                    ).toLocaleString(locale, { dateStyle: "medium" }),
                  })}
                </span>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:targets-progress

export function TargetsProgressSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
