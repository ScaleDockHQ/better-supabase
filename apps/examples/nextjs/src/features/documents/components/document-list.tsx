import { FileTextIcon, TriangleAlertIcon, UsersIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
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
import { Link } from "@/i18n/navigation";

import { getDocuments } from "../documents-queries";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: one notes document per customer. */
export async function DocumentList() {
  const [view, t, format] = await Promise.all([
    getDocuments(),
    getExtracted("documents"),
    getFormatter(),
  ]);

  if (view.kind === "no-organization") {
    return null;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Customer notes")}</CardTitle>
        <CardDescription>
          {t(
            "Each customer has a shared notes document the team edits together.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {view.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The documents didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : view.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileTextIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No documents yet")}</EmptyTitle>
              <EmptyDescription>
                {t("Add a customer to start its notes document.")}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Link href="/customers" className={buttonVariants()}>
                <UsersIcon />
                {t("Go to customers")}
              </Link>
            </EmptyContent>
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Document")}</TableHead>
                <TableHead>{t("Customer updated")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {view.data.map((document) => (
                <TableRow key={document.customerId}>
                  <TableCell className="font-medium">
                    <Link
                      href={`/documents/${document.customerId}`}
                      className="flex items-center gap-2 hover:underline"
                    >
                      <FileTextIcon className="size-4 text-muted-foreground" />
                      {t("Notes for {name}", { name: document.customerName })}
                    </Link>
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {format.dateTime(new Date(document.updatedAt), {
                      dateStyle: "medium",
                    })}
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

export function DocumentListSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
