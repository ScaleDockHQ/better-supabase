import type { ComponentProps } from "react";

// #region recipe:drive-explorer
import {
  FileIcon,
  FolderIcon,
  FolderOpenIcon,
  TriangleAlertIcon,
} from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";
import { Fragment } from "react";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Link } from "@/i18n/navigation";

import type { DriveItem } from "../drive-queries";

import { getDriveFolder } from "../drive-queries";
import { DriveItemActions } from "./drive-item-actions";
import { CreateFolderDialog, UploadFileButton } from "./drive-toolbar";

type Approval = NonNullable<DriveItem["approval"]>;

const APPROVAL_BADGE: Record<
  Approval,
  ComponentProps<typeof Badge>["variant"]
> = {
  pending: "warning-light",
  approved: "success-light",
  rejected: "destructive-light",
  cancelled: "secondary",
  expired: "secondary",
};

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: one folder of the drive (the root for `null`). */
export async function DriveExplorer({
  folderId,
}: {
  folderId: Promise<string | null>;
}) {
  const [view, t, format] = await Promise.all([
    folderId.then(getDriveFolder),
    getExtracted("drive"),
    getFormatter(),
  ]);

  if (view.kind === "no-organization") {
    return null;
  }

  if (view.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="drive-explorer">
        <TriangleAlertIcon />
        <AlertTitle>{t("The drive didn't load")}</AlertTitle>
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

  const current = view.crumbs.at(-1);

  const approvalLabels: Record<Approval, string> = {
    pending: t("Awaiting approval"),
    approved: t("Approved"),
    rejected: t("Rejected"),
    cancelled: t("Approval cancelled"),
    expired: t("Approval expired"),
  };

  return (
    <Card data-recipe="drive-explorer">
      <CardHeader className="flex flex-wrap items-center justify-between gap-3">
        <Breadcrumb>
          <BreadcrumbList>
            <BreadcrumbItem>
              {current === undefined ? (
                <BreadcrumbPage>{t("My drive")}</BreadcrumbPage>
              ) : (
                <BreadcrumbLink render={<Link href="/drive" />}>
                  {t("My drive")}
                </BreadcrumbLink>
              )}
            </BreadcrumbItem>
            {view.crumbs.map((crumb) => (
              <Fragment key={crumb.id}>
                <BreadcrumbSeparator />
                <BreadcrumbItem>
                  {crumb.id === current?.id ? (
                    <BreadcrumbPage>{crumb.name}</BreadcrumbPage>
                  ) : (
                    <BreadcrumbLink
                      render={<Link href={`/drive/${crumb.id}`} />}
                    >
                      {crumb.name}
                    </BreadcrumbLink>
                  )}
                </BreadcrumbItem>
              </Fragment>
            ))}
          </BreadcrumbList>
        </Breadcrumb>
        <div className="flex gap-2">
          <CreateFolderDialog parentId={view.folderId} />
          <UploadFileButton parentId={view.folderId} />
        </div>
      </CardHeader>
      <CardContent>
        {view.items.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FolderOpenIcon />
              </EmptyMedia>
              <EmptyTitle>{t("This folder is empty")}</EmptyTitle>
              <EmptyDescription>
                {t("Create a folder or upload a file to get started.")}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <UploadFileButton parentId={view.folderId} />
            </EmptyContent>
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Name")}</TableHead>
                <TableHead>{t("Size")}</TableHead>
                <TableHead>{t("Added")}</TableHead>
                <TableHead className="w-12">
                  <span className="sr-only">{t("Actions")}</span>
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {view.items.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-medium">
                    <div className="flex flex-col gap-1">
                      {item.kind === "folder" ? (
                        <Link
                          href={`/drive/${item.id}`}
                          className="flex items-center gap-2 transition-colors hover:text-primary"
                        >
                          <FolderIcon className="size-4 text-muted-foreground" />
                          {item.name}
                        </Link>
                      ) : (
                        <span className="flex flex-wrap items-center gap-2">
                          <FileIcon className="size-4 text-muted-foreground" />
                          {item.name}
                          {item.approval === null ? null : (
                            <Badge variant={APPROVAL_BADGE[item.approval]}>
                              {approvalLabels[item.approval]}
                            </Badge>
                          )}
                        </span>
                      )}
                      {item.labels.length === 0 ? null : (
                        <span className="flex flex-wrap gap-1">
                          {item.labels.map((label) => (
                            <Badge key={label.id} variant="outline">
                              {label.name}
                            </Badge>
                          ))}
                        </span>
                      )}
                    </div>
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {item.kind === "folder"
                      ? t("Folder")
                      : item.size === null
                        ? t("Uploading")
                        : t("{size} KB", {
                            size: format.number(item.size / 1024, {
                              maximumFractionDigits: 1,
                            }),
                          })}
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {format.dateTime(new Date(item.createdAt), {
                      dateStyle: "medium",
                    })}
                  </TableCell>
                  <TableCell>
                    <DriveItemActions
                      id={item.id}
                      kind={item.kind}
                      name={item.name}
                      locked={item.locked}
                      downloadBlocked={item.downloadBlocked}
                      downloadable={item.downloadable}
                    />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

export function DriveExplorerSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
// #endregion recipe:drive-explorer
