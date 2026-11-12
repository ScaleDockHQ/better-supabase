import type { ModerationStatus } from "better-supabase/blocks/moderation";

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

import { getItem } from "../moderation-queries";
import { DecideButtons } from "./decide-buttons";
import { STATUS_VARIANT } from "./moderation-labels";

/** One moderated subject: its reports and the log of decisions. */
export async function ModerationDetail({
  type,
  id,
}: {
  type: string;
  id: string;
}) {
  const [item, permissions, t, format] = await Promise.all([
    getItem(type, id),
    getPermissions(),
    getExtracted("moderation"),
    getFormatter(),
  ]);

  if (item === null) {
    notFound();
  }

  const when = (value: string) =>
    format.dateTime(new Date(value), {
      dateStyle: "medium",
      timeStyle: "short",
    });

  const statusLabels: Record<ModerationStatus, string> = {
    pending: t("Pending"),
    visible: t("Visible"),
    hidden: t("Hidden"),
    removed: t("Removed"),
  };

  return (
    <RecordDetailFrame
      title={`${item.subjectType} ${item.subjectId.slice(0, 8)}`}
      description={item.reason ?? undefined}
      status={
        <Badge variant={STATUS_VARIANT[item.status]}>
          {statusLabels[item.status]}
        </Badge>
      }
      actions={
        can(permissions, "moderation.manage") ? (
          <DecideButtons
            itemId={item.id}
            decisions={
              item.status === "hidden" || item.status === "removed"
                ? ["restore"]
                : ["approve", "hide", "remove"]
            }
          />
        ) : null
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Reports")}</CardTitle>
          <CardDescription>
            {t("{count, number} open", { count: item.openReports })}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3 text-sm">
          {item.reports.length === 0 ? (
            <p className="text-muted-foreground">{t("No reports.")}</p>
          ) : (
            item.reports.map((report) => (
              <div key={report.id} className="flex flex-col gap-1">
                <div className="flex items-center gap-2">
                  <span className="font-medium">{report.reason}</span>
                  <Badge variant="secondary">{report.status}</Badge>
                  <span className="text-xs text-muted-foreground">
                    {when(report.createdAt)}
                  </span>
                </div>
                {report.note ? <p>{report.note}</p> : null}
              </div>
            ))
          )}
        </CardContent>
      </Card>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Log")}</CardTitle>
          <CardDescription>
            {t("Every decision and automatic action, newest first.")}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3 text-sm">
          {item.actions.map((action) => (
            <div key={action.id} className="flex items-center gap-2">
              <Badge variant="outline">{action.action}</Badge>
              <span className="text-muted-foreground">
                {statusLabels[action.toStatus]}
                {action.reason ? ` · ${action.reason}` : ""}
              </span>
              <span className="ml-auto text-xs text-muted-foreground">
                {when(action.createdAt)}
              </span>
            </div>
          ))}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function ModerationDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <RecordSectionSkeleton rows={3} />
      <RecordSectionSkeleton rows={3} />
    </div>
  );
}
