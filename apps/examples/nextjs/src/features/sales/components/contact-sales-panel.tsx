import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { Link, toAppHref } from "@/i18n/navigation";

import { loadContactSales } from "../automation/automation-queries";
import { loadMemberOptions } from "../member/member-queries";
import { scoreRecord } from "../sales-actions";
import { ActionButton } from "./action-button";
import { DetailTable } from "./detail-table";
import { FieldHistoryTable } from "./field-history-table";
import { dateFormatter, holds } from "./overview-support";

export function ContactSalesPanelSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}

/**
 * The sales side of a company or person: the segments it is in, its scores and
 * the queues that assigned it. Render it inside `AfterNavigation`, so a
 * prefetch of the contact page holds the head and not these reads.
 */
export async function ContactSalesPanel({
  type,
  id,
}: {
  type: "company" | "person";
  id: string;
}) {
  const [t, loaded, members, fmtDate, canCompute] = await Promise.all([
    getExtracted("sales"),
    settle(() => loadContactSales(type, id)),
    loadMemberOptions(),
    dateFormatter(),
    holds("scores.compute"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The sales details didn't load")} />;
  }

  const { segments, scores, assignments } = loaded.data;
  const nameOf = new Map(members.map((member) => [member.userId, member.name]));

  return (
    <div className="flex flex-col gap-6">
      <DetailTable
        title={t("Scores")}
        description={t("Where this record stands under each score model.")}
        head={[
          t("Model"),
          t("Score"),
          t("Band"),
          t("Matched rules"),
          t("Scored"),
        ]}
        rows={scores.map((score) => ({
          key: score.id,
          cells: [
            score.modelName ?? score.modelKey,
            <span key="s" className="tabular-nums">
              {score.score}
            </span>,
            score.band ? (
              <Badge key="b" variant="secondary">
                {score.band}
              </Badge>
            ) : (
              "–"
            ),
            score.matched.join(", ") || "–",
            fmtDate(score.computedAt),
          ],
        }))}
        emptyTitle={t("Not scored yet")}
        action={
          canCompute ? (
            <ActionButton
              action={scoreRecord}
              input={{ subjectType: type, subjectId: id }}
              label={t("Score now")}
              successMessage={t("Scored")}
            />
          ) : undefined
        }
      />
      <DetailTable
        title={t("Segments")}
        head={[t("Segment"), t("Entered")]}
        rows={segments.map((segment) => ({
          key: segment.segmentId,
          cells: [
            <Link
              key="l"
              href={toAppHref(`/crm/segments/${segment.segmentId}`)}
              className="font-medium hover:underline"
            >
              {segment.name}
            </Link>,
            fmtDate(segment.enteredAt),
          ],
        }))}
        emptyTitle={t("In no segment")}
      />
      <DetailTable
        title={t("Assignment history")}
        head={[t("Owner"), t("Queue"), t("Assigned")]}
        rows={assignments.map((entry) => ({
          key: `${entry.assignedAt}-${entry.userId ?? ""}`,
          cells: [
            entry.userId ? (nameOf.get(entry.userId) ?? entry.userId) : "–",
            entry.queueId ? (
              <Link
                key="q"
                href={toAppHref(`/crm/queues/${entry.queueId}`)}
                className="hover:underline"
              >
                {t("Open queue")}
              </Link>
            ) : (
              "–"
            ),
            fmtDate(entry.assignedAt),
          ],
        }))}
        emptyTitle={t("Never assigned")}
      />
      {type === "company" ? <FieldHistoryTable type="company" id={id} /> : null}
    </div>
  );
}
