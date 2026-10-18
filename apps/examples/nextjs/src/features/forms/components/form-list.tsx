import { ClipboardListIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
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

import { getForms } from "../forms-queries";
import { CreateFormDialog } from "./create-form-dialog";
import { FormStatusBadge } from "./form-status-badge";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** The New form button, for members who may build forms. */
export async function FormManagerActions() {
  const session = await getSession();

  return can(session, "forms.manage") ? <CreateFormDialog /> : null;
}

/** Render inside `<Suspense>`: the organization's forms. */
export async function FormList() {
  const [view, t, format] = await Promise.all([
    getForms(),
    getExtracted("forms"),
    getFormatter(),
  ]);

  if (view.kind === "no-organization") {
    return null;
  }

  if (view.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The forms didn't load")}</AlertTitle>
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

  if (view.data.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <ClipboardListIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No forms yet")}</EmptyTitle>
          <EmptyDescription>
            {t("Build a form to collect answers from your team.")}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <CreateFormDialog />
        </EmptyContent>
      </Empty>
    );
  }

  return (
    <Card>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("Title")}</TableHead>
              <TableHead>{t("Status")}</TableHead>
              <TableHead>{t("Created")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {view.data.map((form) => (
              <TableRow key={form.id}>
                <TableCell>
                  <div className="flex flex-col gap-1">
                    <Link
                      href={`/forms/${form.id}`}
                      className="font-medium transition-colors hover:text-primary"
                    >
                      {form.title}
                    </Link>
                    {form.description ? (
                      <span className="text-xs text-muted-foreground">
                        {form.description}
                      </span>
                    ) : null}
                  </div>
                </TableCell>
                <TableCell>
                  <FormStatusBadge status={form.status} />
                </TableCell>
                <TableCell className="text-muted-foreground">
                  {format.dateTime(new Date(form.createdAt), {
                    dateStyle: "medium",
                  })}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

export function FormListSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
