// #region recipe:form-builder
import type { FormSubmissionStatus } from "better-supabase/blocks/forms";

import { InboxIcon, TriangleAlertIcon } from "lucide-react";
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
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
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

import { type AnswerCell, getForm } from "../forms-queries";
import { FormBuilderWorkspace } from "./form-builder-workspace";
import { FormStatusBadge } from "./form-status-badge";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

const statusVariants = {
  draft: "secondary",
  submitted: "info-light",
  accepted: "success-light",
  rejected: "destructive-light",
} as const satisfies Record<FormSubmissionStatus, string>;

function answerText(
  cell: AnswerCell | undefined,
  yes: string,
  no: string,
): string {
  if (cell === undefined) {
    return "";
  }

  switch (cell.kind) {
    case "text": {
      return cell.text;
    }

    case "bool": {
      return cell.value ? yes : no;
    }

    default: {
      const unhandled: never = cell;

      return unhandled;
    }
  }
}

/** Render inside `<Suspense>`: a form's builder, preview and responses. */
export async function FormBuilder({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const [view, t, format] = await Promise.all([
    getForm(id),
    getExtracted("forms"),
    getFormatter(),
  ]);

  if (view.kind === "no-organization") {
    return null;
  }

  if (view.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="form-builder">
        <TriangleAlertIcon />
        <AlertTitle>{t("The form didn't load")}</AlertTitle>
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

  const { form, version, fields, submissions } = view.data;

  const statusLabels: Record<FormSubmissionStatus, string> = {
    draft: t("Draft"),
    submitted: t("Submitted"),
    accepted: t("Accepted"),
    rejected: t("Rejected"),
  };

  return (
    <div data-recipe="form-builder" className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="text-lg font-semibold">{form.title}</h2>
        <FormStatusBadge status={form.status} />
        <span className="text-xs text-muted-foreground">
          {version === null
            ? t("Not published yet")
            : t("Version {version, number}", { version })}
        </span>
      </div>
      <FormBuilderWorkspace formId={form.id} published={fields} />
      <Card>
        <CardHeader>
          <CardTitle>{t("Responses")}</CardTitle>
          <CardDescription>
            {t("{count, plural, one {# response} other {# responses}}", {
              count: submissions.length,
            })}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {submissions.length === 0 ? (
            <Empty className="border">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <InboxIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No responses yet")}</EmptyTitle>
                <EmptyDescription>
                  {t(
                    "Publish the form, then fill in the preview to add the first response.",
                  )}
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Submitted")}</TableHead>
                  {fields.map((field) => (
                    <TableHead key={field.key}>
                      {field.label ?? field.key}
                    </TableHead>
                  ))}
                  <TableHead>{t("Status")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {submissions.map((submission) => (
                  <TableRow key={submission.id}>
                    <TableCell className="text-muted-foreground">
                      {format.dateTime(new Date(submission.createdAt), {
                        dateStyle: "medium",
                        timeStyle: "short",
                      })}
                    </TableCell>
                    {fields.map((field) => (
                      <TableCell key={field.key}>
                        {answerText(
                          submission.answers[field.key],
                          t("Yes"),
                          t("No"),
                        )}
                      </TableCell>
                    ))}
                    <TableCell>
                      <Badge variant={statusVariants[submission.status]}>
                        {statusLabels[submission.status]}
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

export function FormBuilderSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-8 w-64" />
      <div className="grid gap-6 lg:grid-cols-2">
        <Skeleton className="h-80 rounded-xl" />
        <Skeleton className="h-80 rounded-xl" />
      </div>
      <Skeleton className="h-48 rounded-xl" />
    </div>
  );
}
// #endregion recipe:form-builder
