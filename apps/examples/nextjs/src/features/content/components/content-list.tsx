import { FileTextIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
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
import { PermissionGate } from "@/features/user/components/permission-gate";

import { getContentEntries } from "../content-queries";
import { CONTENT_STATUS_VARIANT, contentStatusLabel } from "./content-labels";
import { ContentRowActions } from "./content-row-actions";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: the pages and posts, newest first. */
export async function ContentList() {
  const [rows, t, format] = await Promise.all([
    getContentEntries().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getExtracted("content"),
    getFormatter(),
  ]);

  if (!rows.ok) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The content didn't load")}</AlertTitle>
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

  if (rows.data.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <FileTextIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No entries yet")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Pages and posts you write here are published to the public site when you say so.",
            )}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t("Title")}</TableHead>
          <TableHead>{t("Type")}</TableHead>
          <TableHead>{t("Status")}</TableHead>
          <TableHead>{t("Updated")}</TableHead>
          <TableHead className="text-right">{t("Actions")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.data.map((row) => (
          <TableRow key={row.id}>
            <TableCell className="font-medium">
              {row.title}
              <span className="block text-xs text-muted-foreground">
                /{row.slug} ({row.locale})
              </span>
            </TableCell>
            <TableCell className="capitalize">{row.type}</TableCell>
            <TableCell>
              <Badge variant={CONTENT_STATUS_VARIANT[row.status]}>
                {contentStatusLabel(t, row.status)}
              </Badge>
            </TableCell>
            <TableCell className="text-xs text-muted-foreground">
              {format.dateTime(new Date(row.updatedAt), {
                dateStyle: "medium",
                timeStyle: "short",
              })}
            </TableCell>
            <TableCell>
              <PermissionGate permission="content.publish">
                <ContentRowActions entryId={row.id} status={row.status} />
              </PermissionGate>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export function ContentListSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
