import { getExtracted } from "next-intl/server";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { CommentThread } from "@/features/customers/components/comment-thread";
import {
  AttachmentsUploader,
  AttachmentsUploaderSkeleton,
} from "@/features/records/components/attachments-uploader";
import {
  RecordTimeline,
  RecordTimelineSkeleton,
} from "@/features/records/components/record-timeline";
import {
  RelatedItemsPanel,
  RelatedItemsPanelSkeleton,
} from "@/features/records/components/related-items-panel";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import type { RecordSubject } from "../record-subject";

import {
  getAttachments,
  getAuthors,
  getRelations,
  getTimeline,
} from "../records-queries";
import { RecordCardSkeleton } from "./record-card-states";

/**
 * Render inside `<Suspense>`: the files of any record, with the upload and
 * remove buttons the caller's keys allow. Renders nothing without
 * `attachments.read`.
 */
// skeleton: RecordFilesSkeleton, exported below
export async function RecordFiles({ subject }: { subject: RecordSubject }) {
  const permissions = await getPermissions();

  if (!can(permissions, "attachments.read")) {
    return null;
  }

  const files = await getAttachments(subject);

  if (files.kind === "hidden") {
    return null;
  }

  return (
    <AttachmentsUploader
      subject={subject}
      files={files}
      canUpload={can(permissions, "attachments.upload")}
      canRemove={can(permissions, "attachments.manage")}
    />
  );
}

/**
 * Render inside `<Suspense>`: the records linked to any record, and a picker
 * for more of its type. Renders nothing without `relations.read`.
 */
// skeleton: RecordRelationsSkeleton, exported below
export async function RecordRelations({ subject }: { subject: RecordSubject }) {
  const permissions = await getPermissions();

  if (!can(permissions, "relations.read")) {
    return null;
  }

  return (
    <RelatedItemsPanel
      subject={subject}
      relations={await getRelations(subject)}
      canManage={can(permissions, "relations.manage")}
    />
  );
}

/**
 * Render inside `<Suspense>`: the latest comments, files and versions of any
 * record in one list.
 */
// skeleton: RecordHistorySkeleton, exported below
export async function RecordHistory({ subject }: { subject: RecordSubject }) {
  const [timeline, authors] = await Promise.all([
    getTimeline(subject),
    getAuthors(),
  ]);

  return <RecordTimeline timeline={timeline} authors={authors} />;
}

// skeleton: RecordDiscussionSkeleton, exported below
/**
 * Render inside `<Suspense>`: the comment thread of any record. `messages.send`
 * decides whether the caller may write.
 */
export async function RecordDiscussion({
  subject,
}: {
  subject: RecordSubject;
}) {
  const [t, permissions, authors] = await Promise.all([
    getExtracted("records"),
    getPermissions(),
    getAuthors(),
  ]);

  return (
    <Card id="comments" data-recipe="comment-thread">
      <CardHeader>
        <CardTitle>{t("Comments")}</CardTitle>
        <CardDescription>
          {t("Visible to everyone in the organization.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <CommentThread
          subject={subject}
          authors={authors}
          canComment={can(permissions, "messages.send")}
        />
      </CardContent>
    </Card>
  );
}

export const RecordFilesSkeleton = AttachmentsUploaderSkeleton;
export const RecordRelationsSkeleton = RelatedItemsPanelSkeleton;
export const RecordHistorySkeleton = RecordTimelineSkeleton;
export const RecordDiscussionSkeleton = RecordCardSkeleton;
