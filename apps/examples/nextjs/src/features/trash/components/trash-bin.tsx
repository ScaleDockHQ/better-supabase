// #region recipe:trash-bin
import { FolderOpenIcon, Trash2Icon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
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
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import { getTrash } from "../trash-queries";
import { TrashItemActions } from "./trash-item-actions";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: what was deleted, with Restore and Delete forever. */
export async function TrashBin() {
  const [view, session, t, format] = await Promise.all([
    getTrash(),
    getSession(),
    getExtracted("trash"),
    getFormatter(),
  ]);

  if (view.kind === "no-organization") {
    return null;
  }

  const kinds = new Map([
    ["customer", t("Customer")],
    ["drive_node", t("Drive item")],
  ]);

  const canPurge = can(session, "trash.manage");

  return (
    <Card data-recipe="trash-bin">
      <CardHeader>
        <CardTitle>{t("Deleted items")}</CardTitle>
        <CardDescription>
          {t(
            "Restore an item to put it back where it was, with everything deleted along with it.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {view.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The trash didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : view.items.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <Trash2Icon />
              </EmptyMedia>
              <EmptyTitle>{t("The trash is empty")}</EmptyTitle>
              <EmptyDescription>
                {t("Items you delete in the drive or elsewhere show up here.")}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Link href="/drive" className={buttonVariants()}>
                <FolderOpenIcon />
                {t("Open the drive")}
              </Link>
            </EmptyContent>
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Item")}</TableHead>
                <TableHead>{t("Type")}</TableHead>
                <TableHead>{t("Deleted")}</TableHead>
                <TableHead>{t("Removed for good")}</TableHead>
                <TableHead className="text-right">{t("Actions")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {view.items.map((item) => {
                const title = item.title ?? t("Untitled");

                return (
                  <TableRow key={item.id}>
                    <TableCell className="font-medium">
                      <div className="flex items-center gap-2">
                        {title}
                        {item.count > 1 ? (
                          <span className="text-xs text-muted-foreground">
                            {t("and {count, number} more", {
                              count: item.count - 1,
                            })}
                          </span>
                        ) : null}
                      </div>
                    </TableCell>
                    <TableCell>
                      <Badge variant="secondary">
                        {kinds.get(item.subjectType) ?? item.subjectType}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {format.dateTime(new Date(item.trashedAt), {
                        dateStyle: "medium",
                        timeStyle: "short",
                      })}
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {item.purgeAfter === null
                        ? t("Never")
                        : format.dateTime(new Date(item.purgeAfter), {
                            dateStyle: "medium",
                          })}
                    </TableCell>
                    <TableCell>
                      <TrashItemActions
                        id={item.id}
                        title={title}
                        canPurge={canPurge}
                      />
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

export function TrashBinSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
// #endregion recipe:trash-bin
