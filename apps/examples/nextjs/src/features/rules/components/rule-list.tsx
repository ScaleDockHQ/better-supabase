import { ListFilterIcon, PlusIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden } from "next/navigation";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
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
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { retryRules } from "../rules-actions";
import { getRules } from "../rules-queries";

/** Render inside `<Suspense>`: the customer rules in evaluation order. */
export async function RuleList() {
  const [t, format, permissions] = await Promise.all([
    getExtracted("rules"),
    getFormatter(),
    getPermissions(),
  ]);

  if (!can(permissions, "rules.read")) {
    forbidden();
  }

  const rules = await getRules();

  if (rules.kind === "no-organization") {
    return null;
  }

  const canEdit = can(permissions, "rules.edit");

  const newRule = (
    <Link
      href="/rules/new"
      className={buttonVariants({ size: "sm" })}
      data-testid="new-rule"
    >
      <PlusIcon />
      {t("New rule")}
    </Link>
  );

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Customer rules")}</CardTitle>
        <CardDescription>
          {t("Rules run in this order each time a customer is saved.")}
        </CardDescription>
        {canEdit && rules.kind === "ok" && rules.data.length > 0 ? (
          <CardAction>{newRule}</CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {rules.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The rules didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retryRules}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : rules.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ListFilterIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No rules yet")}</EmptyTitle>
              <EmptyDescription>
                {canEdit
                  ? t("Add a rule to act on leads that match its conditions.")
                  : t("Rules your admins add show up here.")}
              </EmptyDescription>
            </EmptyHeader>
            {canEdit ? <EmptyContent>{newRule}</EmptyContent> : null}
          </Empty>
        ) : (
          <ul className="divide-y" data-testid="rule-list">
            {rules.data.map((rule) => (
              <li
                key={rule.id}
                className="flex items-center justify-between gap-4 py-3 text-sm"
              >
                <Link href={`/rules/${rule.id}`} className="font-medium">
                  {rule.name || t("Untitled rule")}
                </Link>
                <span className="flex items-center gap-2">
                  <span className="text-xs text-muted-foreground">
                    {t(
                      "{count, plural, one {# condition} other {# conditions}}",
                      { count: rule.conditions },
                    )}
                  </span>
                  {rule.enabled ? (
                    <Badge variant="success-light">{t("On")}</Badge>
                  ) : (
                    <Badge variant="outline">{t("Off")}</Badge>
                  )}
                  <span className="text-xs text-muted-foreground tabular-nums">
                    {format.dateTime(new Date(rule.updatedAt), {
                      dateStyle: "medium",
                    })}
                  </span>
                </span>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

export function RuleListSkeleton() {
  return <Skeleton className="h-64" aria-busy="true" />;
}
