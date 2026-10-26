import { tenantOf } from "better-supabase/next";
import { getExtracted, getFormatter } from "next-intl/server";
import Image from "next/image";
import { notFound } from "next/navigation";
import { Suspense } from "react";

import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getMembers } from "@/features/organization/organization-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { initials } from "@/lib/initials";

import { getCustomer } from "../customer-queries";
import {
  getAttachments,
  getRelations,
  getShareLinks,
  getSlaClocks,
  getTimeline,
  getVersions,
} from "../customer-record-queries";
import {
  AttachmentsUploader,
  AttachmentsUploaderSkeleton,
} from "./attachments-uploader";
import { CommentThread } from "./comment-thread";
import { CustomerLogoForm } from "./customer-logo-form";
import { CustomerStatus } from "./customer-status";
import {
  CustomerTimeline,
  CustomerTimelineSkeleton,
} from "./customer-timeline";
import { ReactionsBar } from "./reactions-bar";
import {
  RelatedItemsPanel,
  RelatedItemsPanelSkeleton,
} from "./related-items-panel";
import { ShareLinkDialog, ShareLinkDialogSkeleton } from "./share-link-dialog";
import { SlaBadges, SlaBadgesSkeleton } from "./sla-badges";
import { TagInput } from "./tag-input";
import { VersionHistory, VersionHistorySkeleton } from "./version-history";

async function ShareLinksSection({
  customerId,
  canCreate,
}: {
  customerId: string;
  canCreate: boolean;
}) {
  const links = await getShareLinks(customerId);

  return (
    <ShareLinkDialog
      customerId={customerId}
      links={links}
      canCreate={canCreate}
    />
  );
}

async function AttachmentsSection({
  customerId,
  canUpload,
  canRemove,
}: {
  customerId: string;
  canUpload: boolean;
  canRemove: boolean;
}) {
  const files = await getAttachments(customerId);

  if (files.kind === "hidden") {
    return null;
  }

  return (
    <AttachmentsUploader
      customerId={customerId}
      files={files}
      canUpload={canUpload}
      canRemove={canRemove}
    />
  );
}

async function RelationsSection({
  customerId,
  canManage,
}: {
  customerId: string;
  canManage: boolean;
}) {
  const relations = await getRelations(customerId);

  return (
    <RelatedItemsPanel
      customerId={customerId}
      relations={relations}
      canManage={canManage}
    />
  );
}

async function VersionsSection({
  customerId,
  canSave,
  canRestore,
}: {
  customerId: string;
  canSave: boolean;
  canRestore: boolean;
}) {
  const versions = await getVersions(customerId);

  return (
    <VersionHistory
      customerId={customerId}
      versions={versions}
      canSave={canSave}
      canRestore={canRestore}
    />
  );
}

async function SlaSection({
  customerId,
  canCreatePolicy,
}: {
  customerId: string;
  canCreatePolicy: boolean;
}) {
  const clocks = await getSlaClocks(customerId);

  return (
    <SlaBadges
      customerId={customerId}
      clocks={clocks}
      canCreatePolicy={canCreatePolicy}
    />
  );
}

async function TimelineSection({
  customerId,
  authors,
}: {
  customerId: string;
  authors: Readonly<Record<string, string>>;
}) {
  const timeline = await getTimeline(customerId);

  return <CustomerTimeline timeline={timeline} authors={authors} />;
}

/** Render inside `<Suspense>`: reads the `id` param and the session. */
export async function CustomerDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const [{ id }, session, permissions] = await Promise.all([
    params,
    getSession(),
    getPermissions(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    notFound();
  }

  const [customer, members, t, format] = await Promise.all([
    getCustomer(id),
    getMembers(organizationId),
    getExtracted("customers"),
    getFormatter(),
  ]);

  if (!customer) {
    notFound();
  }

  const authors = Object.fromEntries(
    members.flatMap((member) => {
      const name = member.name ?? member.email;

      return name ? [[member.userId, name]] : [];
    }),
  );

  const customerId = customer.id;

  return (
    <div className="grid items-start gap-6 lg:grid-cols-3">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <div className="flex items-center gap-4">
          {customer.logoUrl ? (
            <Image
              src={customer.logoUrl}
              width={56}
              height={56}
              alt=""
              className="rounded-xl"
            />
          ) : (
            <span className="flex size-14 items-center justify-center rounded-xl bg-muted text-lg font-semibold text-muted-foreground">
              {initials(customer.name, null)}
            </span>
          )}
          <div className="flex flex-col gap-1">
            <h1 className="text-2xl font-semibold tracking-tight">
              {customer.name}
            </h1>
            <p className="text-sm text-muted-foreground">
              {t("Customer since {date}", {
                date: format.dateTime(new Date(customer.createdAt), {
                  dateStyle: "long",
                }),
              })}
            </p>
          </div>
          <CustomerStatus status={customer.status} />
        </div>

        {can(permissions, "reactions.read") ? (
          <ReactionsBar
            customerId={customerId}
            canReact={can(permissions, "reactions.create")}
          />
        ) : null}

        <Card id="comments" data-recipe="comment-thread">
          <CardHeader>
            <CardTitle>{t("Comments")}</CardTitle>
            <CardDescription>
              {t("Visible to everyone in the organization.")}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <CommentThread
              subject={{ type: "customer", id: customer.id }}
              authors={authors}
              canComment={can(permissions, "messages.send")}
            />
          </CardContent>
        </Card>

        {can(permissions, "attachments.read") ? (
          <Suspense fallback={<AttachmentsUploaderSkeleton />}>
            <AttachmentsSection
              customerId={customerId}
              canUpload={can(permissions, "attachments.upload")}
              canRemove={can(permissions, "attachments.manage")}
            />
          </Suspense>
        ) : null}
        {can(permissions, "relations.read") ? (
          <Suspense fallback={<RelatedItemsPanelSkeleton />}>
            <RelationsSection
              customerId={customerId}
              canManage={can(permissions, "relations.manage")}
            />
          </Suspense>
        ) : null}
        {can(permissions, "versions.read") ? (
          <Suspense fallback={<VersionHistorySkeleton />}>
            <VersionsSection
              customerId={customerId}
              canSave={can(permissions, "versions.create")}
              canRestore={
                can(permissions, "versions.restore") &&
                can(permissions, "customers.write")
              }
            />
          </Suspense>
        ) : null}
      </div>

      <div className="flex flex-col gap-6">
        <Suspense fallback={<CustomerTimelineSkeleton />}>
          <TimelineSection customerId={customerId} authors={authors} />
        </Suspense>
        {can(permissions, "sla.read") ? (
          <Suspense fallback={<SlaBadgesSkeleton />}>
            <SlaSection
              customerId={customerId}
              canCreatePolicy={can(permissions, "sla.manage")}
            />
          </Suspense>
        ) : null}
        {can(permissions, "share_links.read") ? (
          <Suspense fallback={<ShareLinkDialogSkeleton />}>
            <ShareLinksSection
              customerId={customerId}
              canCreate={can(permissions, "share_links.create")}
            />
          </Suspense>
        ) : null}
        <Card size="sm" data-recipe="tag-input">
          <CardHeader>
            <CardTitle>{t("Tags")}</CardTitle>
          </CardHeader>
          <CardContent>
            <TagInput subject={{ type: "customer", id: customer.id }} />
          </CardContent>
        </Card>
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Recent notes")}</CardTitle>
          </CardHeader>
          <CardContent>
            {customer.notes.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                {t("No notes yet.")}
              </p>
            ) : (
              <ul className="flex flex-col gap-3">
                {customer.notes.map((note) => (
                  <li
                    key={note.id}
                    className="flex flex-col items-start gap-1 text-sm"
                  >
                    <p>{note.body}</p>
                    <Badge variant="outline">{note.kind}</Badge>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
        {can(permissions, "customers.write") ? (
          <Card size="sm">
            <CardContent>
              <CustomerLogoForm customerId={customer.id} />
            </CardContent>
          </Card>
        ) : null}
      </div>
    </div>
  );
}

export function CustomerDetailSkeleton() {
  return (
    <div className="grid items-start gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <div className="flex items-center gap-4">
          <Skeleton className="size-14 rounded-xl" />
          <Skeleton className="h-8 w-48" />
        </div>
        <Skeleton className="h-24 rounded-xl" />
        <Skeleton className="h-72 rounded-xl" />
        <Skeleton className="h-40 rounded-xl" />
      </div>
      <div className="flex flex-col gap-6">
        <Skeleton className="h-32 rounded-xl" />
        <Skeleton className="h-32 rounded-xl" />
        <Skeleton className="h-48 rounded-xl" />
      </div>
    </div>
  );
}
