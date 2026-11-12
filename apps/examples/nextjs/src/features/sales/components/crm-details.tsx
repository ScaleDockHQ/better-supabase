import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { Link, toAppHref } from "@/i18n/navigation";

import {
  loadQueue,
  loadScoreModel,
  loadSegment,
} from "../automation/automation-queries";
import { loadMemberOptions } from "../member/member-queries";
import {
  deleteSegment,
  refreshSegment,
  setQueueEnabled,
  setScoreModelEnabled,
} from "../sales-actions";
import { ActionButton } from "./action-button";
import { DetailTable, FactGrid } from "./detail-table";
import { dateFormatter, holds, requirePermission } from "./overview-support";
import { QueueMembersEditor } from "./queue-members-editor";

export function SalesDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

const RECORD_PATH = new Map<string, string>([
  ["company", "/crm/contacts/"],
  ["person", "/crm/contacts/"],
  ["deal", "/crm/deals/"],
]);

/** A segment with its newest members, a refresh and a delete. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function SegmentDetail({ id }: { id: string }) {
  await requirePermission("segments.read");

  const [t, loaded, fmtDate, canWrite] = await Promise.all([
    getExtracted("sales"),
    settle(() => loadSegment(id)),
    dateFormatter(),
    holds("segments.write"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The segment didn't load")} />;
  }

  const segment = loaded.data;

  if (!segment) {
    notFound();
  }

  return (
    <RecordDetailFrame
      title={segment.name}
      description={segment.description ?? undefined}
      status={<Badge variant="secondary">{segment.subjectType}</Badge>}
      actions={
        canWrite ? (
          <>
            <ActionButton
              action={refreshSegment}
              input={{ segmentId: segment.id }}
              label={t("Refresh now")}
              successMessage={t("Segment refreshed")}
            />
            <ActionButton
              action={deleteSegment}
              input={{ segmentId: segment.id }}
              label={t("Delete")}
              successMessage={t("Segment deleted")}
              variant="ghost"
              redirectTo="/crm/segments"
            />
          </>
        ) : undefined
      }
    >
      <FactGrid
        facts={[
          { label: t("Members"), value: String(segment.memberCount) },
          { label: t("Rules"), value: String(segment.rules) },
          { label: t("Last refresh"), value: fmtDate(segment.refreshedAt) },
        ]}
      />
      <DetailTable
        title={t("Newest members")}
        description={t("The records that matched at the last refresh.")}
        head={[t("Record"), t("Entered")]}
        rows={segment.members.map((member) => ({
          key: member.subjectId,
          cells: [
            RECORD_PATH.has(segment.subjectType) ? (
              <Link
                key="link"
                href={toAppHref(
                  `${RECORD_PATH.get(segment.subjectType)}${member.subjectId}`,
                )}
                className="font-medium hover:underline"
              >
                {member.subjectId}
              </Link>
            ) : (
              member.subjectId
            ),
            fmtDate(member.enteredAt),
          ],
        }))}
        emptyTitle={t("No members yet")}
        emptyDescription={t("Refresh the segment to evaluate its rule.")}
      />
    </RecordDetailFrame>
  );
}

/** A queue with its members, weights and assignment counts. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function QueueDetail({ id }: { id: string }) {
  await requirePermission("assignment.read");

  const [t, loaded, options, canManage] = await Promise.all([
    getExtracted("sales"),
    settle(() => loadQueue(id)),
    loadMemberOptions(),
    holds("assignment.manage"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The queue didn't load")} />;
  }

  const queue = loaded.data;

  if (!queue) {
    notFound();
  }

  const nameOf = new Map(options.map((option) => [option.userId, option.name]));

  return (
    <RecordDetailFrame
      title={queue.name}
      description={
        queue.strategy === "weighted" ? t("Weighted") : t("Round robin")
      }
      status={
        <Badge variant={queue.enabled ? "success-light" : "warning-light"}>
          {queue.enabled ? t("Enabled") : t("Paused")}
        </Badge>
      }
      actions={
        canManage ? (
          <ActionButton
            action={setQueueEnabled}
            input={{ queueId: queue.id, enabled: !queue.enabled }}
            label={queue.enabled ? t("Pause queue") : t("Enable queue")}
            successMessage={t("Queue updated")}
          />
        ) : undefined
      }
    >
      <FactGrid
        facts={[
          { label: t("Assigns"), value: queue.subjectType },
          { label: t("Members"), value: String(queue.members) },
          { label: t("Assigned"), value: String(queue.assigned) },
        ]}
      />
      <QueueMembersEditor
        queueId={queue.id}
        members={queue.memberRows.map((member) => ({
          userId: member.userId,
          name: nameOf.get(member.userId) ?? member.userId,
          weight: member.weight,
          active: member.active,
          assigned: member.assignedCount,
        }))}
        candidates={options}
        canManage={canManage}
      />
    </RecordDetailFrame>
  );
}

/** A score model with its rules, bands, versions and top-scored records. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ScoreModelDetail({ id }: { id: string }) {
  await requirePermission("scores.read");

  const [t, loaded, fmtDate, canManage, canCompute] = await Promise.all([
    getExtracted("sales"),
    settle(() => loadScoreModel(id)),
    dateFormatter(),
    holds("scores.manage"),
    holds("scores.compute"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The score model didn't load")} />;
  }

  const detail = loaded.data;

  if (!detail) {
    notFound();
  }

  const { model, top } = detail;

  return (
    <RecordDetailFrame
      title={model.name}
      description={model.description ?? model.key}
      status={
        <Badge variant={model.enabled ? "success-light" : "warning-light"}>
          {model.enabled ? t("Enabled") : t("Paused")}
        </Badge>
      }
      actions={
        canManage ? (
          <ActionButton
            action={setScoreModelEnabled}
            input={{ modelId: model.id, enabled: !model.enabled }}
            label={model.enabled ? t("Pause model") : t("Enable model")}
            successMessage={t("Model updated")}
          />
        ) : undefined
      }
    >
      <FactGrid
        facts={[
          { label: t("Scores"), value: model.subjectType },
          { label: t("Version"), value: String(model.version) },
          { label: t("Bands"), value: model.bands || "–" },
        ]}
      />
      <DetailTable
        title={t("Rules")}
        head={[t("Rule"), t("Points")]}
        rows={model.ruleRows.map((rule) => ({
          key: rule.id,
          cells: [
            rule.label,
            <span key="p" className="tabular-nums">
              {rule.points}
            </span>,
          ],
        }))}
        emptyTitle={t("No rules")}
      />
      <DetailTable
        title={t("Top scores")}
        description={t("The highest current scores under this model.")}
        head={[
          t("Record"),
          t("Score"),
          t("Band"),
          t("Matched rules"),
          t("Scored"),
        ]}
        rows={top.map((score) => ({
          key: score.id,
          cells: [
            RECORD_PATH.has(score.subjectType) ? (
              <Link
                key="l"
                href={toAppHref(
                  `${RECORD_PATH.get(score.subjectType)}${score.subjectId}`,
                )}
                className="font-medium hover:underline"
              >
                {score.subjectId}
              </Link>
            ) : (
              score.subjectId
            ),
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
        emptyTitle={t("Nothing scored yet")}
        emptyDescription={
          canCompute
            ? t(
                "Open a company and score it, or let the lead model run on a schedule.",
              )
            : undefined
        }
      />
      <DetailTable
        title={t("Versions")}
        head={[t("Version"), t("Saved")]}
        rows={model.versions.map((version) => ({
          key: String(version.version),
          cells: [String(version.version), fmtDate(version.savedAt)],
        }))}
        emptyTitle={t("No earlier versions")}
      />
    </RecordDetailFrame>
  );
}
