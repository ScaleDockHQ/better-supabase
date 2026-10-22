import type {
  ComponentStatus,
  IncidentStatus,
} from "better-supabase/blocks/incidents";

import {
  ActivityIcon,
  CircleCheckIcon,
  TriangleAlertIcon,
  WrenchIcon,
} from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
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
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";

import { loadStatusPage, settle, UPTIME_DAYS } from "../status-queries";

// #region recipe:status-page
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

type Translate = Awaited<ReturnType<typeof getExtracted>>;

type BadgeVariant =
  | "success-light"
  | "info-light"
  | "warning-light"
  | "destructive-light";

interface StatusLook {
  readonly label: string;
  readonly badge: BadgeVariant;
  /** The background of an uptime cell. */
  readonly cell: string;
}

function statusLook(status: ComponentStatus, t: Translate): StatusLook {
  switch (status) {
    case "operational": {
      return {
        label: t("Operational"),
        badge: "success-light",
        cell: "bg-success",
      };
    }

    case "maintenance": {
      return { label: t("Maintenance"), badge: "info-light", cell: "bg-info" };
    }

    case "degraded": {
      return {
        label: t("Degraded performance"),
        badge: "warning-light",
        cell: "bg-warning",
      };
    }

    case "partial_outage": {
      return {
        label: t("Partial outage"),
        badge: "warning-light",
        cell: "bg-warning",
      };
    }

    case "major_outage": {
      return {
        label: t("Major outage"),
        badge: "destructive-light",
        cell: "bg-destructive",
      };
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

function updateLabel(status: IncidentStatus, t: Translate): string {
  switch (status) {
    case "investigating": {
      return t("Investigating");
    }

    case "identified": {
      return t("Identified");
    }

    case "monitoring": {
      return t("Monitoring");
    }

    case "resolved": {
      return t("Resolved");
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

function OverallAlert({
  status,
  t,
}: {
  status: ComponentStatus;
  t: Translate;
}) {
  switch (status) {
    case "operational": {
      return (
        <Alert variant="success">
          <CircleCheckIcon />
          <AlertTitle>{t("All systems operational")}</AlertTitle>
        </Alert>
      );
    }

    case "maintenance": {
      return (
        <Alert variant="info">
          <WrenchIcon />
          <AlertTitle>{t("Scheduled maintenance in progress")}</AlertTitle>
        </Alert>
      );
    }

    case "degraded":
    case "partial_outage": {
      return (
        <Alert variant="warning">
          <TriangleAlertIcon />
          <AlertTitle>{t("Some systems are affected")}</AlertTitle>
        </Alert>
      );
    }

    case "major_outage": {
      return (
        <Alert variant="destructive">
          <TriangleAlertIcon />
          <AlertTitle>{t("Major outage")}</AlertTitle>
        </Alert>
      );
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

/**
 * The public status page published at `slug`: the overall status, each public
 * component with its uptime, then the public incidents with their updates.
 * Anyone can open it; the incidents block returns only fields marked public.
 */
export async function StatusPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const [{ slug }, t, format] = await Promise.all([
    params,
    getExtracted("status"),
    getFormatter(),
  ]);

  const page = await settle(() => loadStatusPage(slug));

  if (page.kind === "missing") {
    notFound();
  }

  if (page.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="status-page">
        <TriangleAlertIcon />
        <AlertTitle>{t("The status page didn't load")}</AlertTitle>
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

  const { data } = page;

  const day = (date: string) =>
    format.dateTime(new Date(`${date}T12:00:00Z`), {
      dateStyle: "medium",
      timeZone: "UTC",
    });

  const when = (iso: string) =>
    format.dateTime(new Date(iso), { dateStyle: "medium", timeStyle: "short" });

  return (
    <div className="flex flex-col gap-6" data-recipe="status-page">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold tracking-tight">{data.title}</h1>
        {data.description ? (
          <p className="text-sm text-muted-foreground">{data.description}</p>
        ) : null}
      </div>
      <OverallAlert status={data.status} t={t} />
      <Card>
        <CardHeader>
          <CardTitle>{t("Components")}</CardTitle>
          <CardDescription>
            {t("Uptime over the last {days, number} days.", {
              days: UPTIME_DAYS,
            })}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {data.components.length === 0 ? (
            <Empty className="border">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <ActivityIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No components yet")}</EmptyTitle>
                <EmptyDescription>
                  {t(
                    "Components appear here once the team marks them public. Check back later.",
                  )}
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <ul className="flex flex-col gap-6">
              {data.components.map((component) => {
                const look = statusLook(component.status, t);

                return (
                  <li key={component.id} className="flex flex-col gap-2">
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-sm font-medium">
                        {component.name}
                      </span>
                      <Badge variant={look.badge}>{look.label}</Badge>
                    </div>
                    <div className="flex h-8 gap-px" aria-hidden="true">
                      {component.uptime.map((entry) => (
                        <span
                          key={entry.date}
                          className={`flex-1 rounded-sm ${statusLook(entry.status, t).cell}`}
                          title={`${day(entry.date)}: ${statusLook(entry.status, t).label}`}
                        />
                      ))}
                    </div>
                    <span className="text-xs text-muted-foreground tabular-nums">
                      {t("{percent, number}% uptime", {
                        percent: component.uptimePercent,
                      })}
                    </span>
                  </li>
                );
              })}
            </ul>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Incidents")}</CardTitle>
          <CardDescription>
            {t(
              "Open incidents and those resolved in the last {days, number} days.",
              { days: UPTIME_DAYS },
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {data.incidents.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("No incidents reported.")}
            </p>
          ) : (
            <ul className="flex flex-col gap-6">
              {data.incidents.map((incident) => (
                <li key={incident.id} className="flex flex-col gap-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="text-sm font-medium">
                      {incident.title}
                    </span>
                    <Badge
                      variant={
                        incident.status === "resolved"
                          ? "success-light"
                          : "warning-light"
                      }
                    >
                      {updateLabel(incident.status, t)}
                    </Badge>
                  </div>
                  {incident.components.length > 0 ? (
                    <p className="text-xs text-muted-foreground">
                      {t("Affects {components}", {
                        components: incident.components
                          .map((component) => component.name)
                          .join(", "),
                      })}
                    </p>
                  ) : null}
                  <ol className="flex flex-col gap-3 border-l pl-4">
                    {incident.updates.map((update) => (
                      <li
                        key={update.createdAt}
                        className="flex flex-col gap-1"
                      >
                        <span className="text-xs text-muted-foreground">
                          {updateLabel(update.status, t)}
                          {" · "}
                          {when(update.createdAt)}
                        </span>
                        <p className="text-sm">{update.body}</p>
                      </li>
                    ))}
                  </ol>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

export function StatusPageSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-12 rounded-xl" />
      <Skeleton className="h-64 rounded-xl" />
    </div>
  );
}
// #endregion recipe:status-page
