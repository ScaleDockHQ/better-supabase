import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { publishEntryWithVersion } from "@/features/composites/composites-actions";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { ActionButton } from "@/features/sales/components/action-button";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import {
  dateFormatter,
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { archiveEntry } from "../content-actions";
import { getContentEntry } from "../content-queries";

export function ContentDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

/** The entry's page: status, publish actions, properties and record sections. */
export async function ContentDetail({ id, tab }: { id: string; tab: string }) {
  await requirePermission("content.read");

  const [t, loaded, fmtDate, canPublish] = await Promise.all([
    getExtracted("content"),
    settle(() => getContentEntry(id)),
    dateFormatter(),
    holds("content.publish"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The entry didn't load")} />;
  }

  const entry = loaded.data;

  if (!entry) {
    notFound();
  }

  const subject = { type: "content_entry", id: entry.id } as const;
  const live = entry.status === "published";

  const facts = [
    { label: t("Type"), value: entry.type },
    { label: t("Slug"), value: `/${entry.slug}` },
    { label: t("Locale"), value: entry.locale },
    { label: t("Updated"), value: fmtDate(entry.updatedAt) },
    { label: t("Published"), value: fmtDate(entry.publishedAt) },
    { label: t("Scheduled for"), value: fmtDate(entry.publishAt) },
    { label: t("Translations"), value: String(entry.translations) },
  ];

  return (
    <RecordDetailFrame
      aside={
        <>
          <PropertiesRail title={t("Details")} properties={facts} />
          <RecordBoundSections
            subject={subject}
            sections={["tags", "fields", "approvals", "reminders"]}
          />
        </>
      }
      title={entry.title}
      description={entry.summary ?? undefined}
      status={
        <Badge
          variant={
            live
              ? "success-light"
              : entry.status === "scheduled"
                ? "info-light"
                : entry.status === "archived"
                  ? "warning-light"
                  : "secondary"
          }
        >
          {
            {
              draft: t("Draft"),
              scheduled: t("Scheduled"),
              published: t("Published"),
              archived: t("Archived"),
            }[entry.status]
          }
        </Badge>
      }
      actions={
        canPublish ? (
          <>
            {entry.status === "draft" || entry.status === "scheduled" ? (
              <ActionDialog
                action={publishEntryWithVersion}
                title={t("Publish with a version")}
                description={t(
                  "Keeps a version of the content, then publishes the entry.",
                )}
                trigger={t("Publish with version")}
                submitLabel={t("Publish")}
                successMessage={t("Entry published with a version")}
                hidden={{ entryId: entry.id }}
                fields={[
                  {
                    name: "label",
                    label: t("Version label (optional)"),
                    kind: "text",
                    placeholder: t("Spring launch"),
                  },
                ]}
              />
            ) : null}
            {entry.status === "archived" ? null : (
              <ActionButton
                action={archiveEntry}
                input={{ entryId: entry.id }}
                label={t("Archive")}
                successMessage={t("Entry archived")}
              />
            )}
          </>
        ) : undefined
      }
    >
      <RecordDetailTabs
        base={`/content/${id}`}
        active={tab}
        tabs={[
          { value: "overview", label: t("Overview") },
          { value: "activity", label: t("Activity") },
          { value: "related", label: t("Related") },
        ]}
      />
      {tab === "related" ? (
        <RecordBoundSections
          subject={subject}
          sections={["files", "relations"]}
        />
      ) : tab === "activity" ? (
        <RecordBoundSections
          subject={subject}
          sections={["discussion", "history"]}
        />
      ) : (
        <Card>
          <CardHeader>
            <CardTitle>{t("Publishing")}</CardTitle>
            <CardDescription>
              {live
                ? t("The entry is live on the public site.")
                : t("Only published entries reach the public site.")}
            </CardDescription>
          </CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            {entry.approvalStatus === null
              ? t("No publish request is open.")
              : t("Publish request: {status}", {
                  status: entry.approvalStatus,
                })}
          </CardContent>
        </Card>
      )}
    </RecordDetailFrame>
  );
}
