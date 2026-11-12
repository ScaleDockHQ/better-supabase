import type { IncidentStatus } from "better-supabase/blocks/incidents";

import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getIncident } from "../incidents-queries";
import { SEVERITY_VARIANT, STATUS_VARIANT } from "./incident-labels";
import { IncidentUpdateForm } from "./incident-update-form";

/** One incident: head, description and the timeline with the update form. */
export async function IncidentDetail({ id }: { id: string }) {
  const [incident, permissions, t, format] = await Promise.all([
    getIncident(id),
    getPermissions(),
    getExtracted("incidents"),
    getFormatter(),
  ]);

  if (incident === null) {
    notFound();
  }

  const when = (value: string) =>
    format.dateTime(new Date(value), {
      dateStyle: "medium",
      timeStyle: "short",
    });

  const statusLabels: Record<IncidentStatus, string> = {
    investigating: t("Investigating"),
    identified: t("Identified"),
    monitoring: t("Monitoring"),
    resolved: t("Resolved"),
  };

  return (
    <RecordDetailFrame
      title={incident.title}
      description={t("Started {when}", { when: when(incident.startedAt) })}
      status={
        <>
          <Badge variant={SEVERITY_VARIANT[incident.severity]}>
            {incident.severity.toUpperCase()}
          </Badge>
          <Badge variant={STATUS_VARIANT[incident.status]}>
            {statusLabels[incident.status]}
          </Badge>
        </>
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Details")}</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-2 gap-2 text-sm">
            <span className="text-muted-foreground">{t("Visibility")}</span>
            <span className="text-right">
              {incident.public ? t("Public") : t("Members only")}
            </span>
            <span className="text-muted-foreground">{t("Components")}</span>
            <span className="text-right tabular-nums">
              {incident.impactCount}
            </span>
            <span className="text-muted-foreground">{t("Resolved")}</span>
            <span className="text-right">
              {incident.resolvedAt ? when(incident.resolvedAt) : "–"}
            </span>
            <span className="text-muted-foreground">{t("Postmortem")}</span>
            <span className="text-right">
              {incident.postmortemStatus === "published"
                ? t("Published")
                : incident.postmortemStatus === "draft"
                  ? t("Draft")
                  : "–"}
            </span>
          </CardContent>
        </Card>
      }
    >
      {incident.description ? (
        <p className="text-sm">{incident.description}</p>
      ) : null}
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Timeline")}</CardTitle>
          <CardDescription>{t("Every update, newest first.")}</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {can(permissions, "incidents.write") &&
          incident.status !== "resolved" ? (
            <IncidentUpdateForm incidentId={incident.id} />
          ) : null}
          {incident.updates.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("No updates yet.")}
            </p>
          ) : (
            <ol className="flex flex-col gap-3">
              {incident.updates
                .toSorted((a, b) => b.createdAt.localeCompare(a.createdAt))
                .map((update) => (
                  <li key={update.id} className="flex flex-col gap-1 text-sm">
                    <div className="flex items-center gap-2">
                      <Badge variant={STATUS_VARIANT[update.status]}>
                        {statusLabels[update.status]}
                      </Badge>
                      <span className="text-xs text-muted-foreground">
                        {when(update.createdAt)}
                      </span>
                    </div>
                    <p>{update.body}</p>
                  </li>
                ))}
            </ol>
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function IncidentDetailSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <RecordSectionSkeleton rows={4} />
      </div>
      <RecordSectionSkeleton rows={4} />
    </div>
  );
}
