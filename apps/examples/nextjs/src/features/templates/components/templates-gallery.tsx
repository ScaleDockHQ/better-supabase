// #region recipe:templates-gallery
import { LayoutTemplateIcon, TriangleAlertIcon } from "lucide-react";
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
  CardFooter,
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
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getTemplates } from "../templates-queries";
import { CreateTemplateDialog } from "./create-template-dialog";
import { UseTemplateDialog } from "./use-template-dialog";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** The New template button, for members who may manage templates. */
export async function TemplateManagerActions() {
  const session = await getSession();

  return can(session, "templates.manage") ? <CreateTemplateDialog /> : null;
}

/** Render inside `<Suspense>`: the customer templates, each with Use template. */
export async function TemplatesGallery() {
  const [view, session, t, format] = await Promise.all([
    getTemplates(),
    getSession(),
    getExtracted("templates"),
    getFormatter(),
  ]);

  if (view.kind === "no-organization") {
    return null;
  }

  const canApply =
    can(session, "templates.apply") && can(session, "customers.write");

  if (view.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="templates-gallery">
        <TriangleAlertIcon />
        <AlertTitle>{t("The templates didn't load")}</AlertTitle>
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

  if (view.templates.length === 0) {
    return (
      <Empty className="border" data-recipe="templates-gallery">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <LayoutTemplateIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No templates yet")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "A template holds the values a new customer starts with, so the team sets them up the same way.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        {can(session, "templates.manage") ? (
          <EmptyContent>
            <CreateTemplateDialog />
          </EmptyContent>
        ) : null}
      </Empty>
    );
  }

  return (
    <div
      className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3"
      data-recipe="templates-gallery"
    >
      {view.templates.map((template) => (
        <Card key={template.id}>
          <CardHeader>
            <CardTitle>{template.name}</CardTitle>
            <CardDescription>
              {t("Updated {date}", {
                date: format.dateTime(new Date(template.updatedAt), {
                  dateStyle: "medium",
                }),
              })}
            </CardDescription>
          </CardHeader>
          <CardContent className="flex flex-wrap items-center gap-2">
            {template.status === null ? null : (
              <Badge variant="info-light">
                {template.status === "active" ? t("Active") : t("Lead")}
              </Badge>
            )}
            {template.publishedVersion === null ? (
              <Badge variant="warning-light">{t("Not published")}</Badge>
            ) : (
              <Badge variant="outline">
                {t("Version {version}", {
                  version: String(template.publishedVersion),
                })}
              </Badge>
            )}
            {template.scope === "system" ? (
              <Badge variant="secondary">{t("Built in")}</Badge>
            ) : null}
            {template.isDefault ? (
              <Badge variant="success-light">{t("Default")}</Badge>
            ) : null}
          </CardContent>
          <CardFooter>
            <UseTemplateDialog
              templateId={template.id}
              templateName={template.name}
              disabled={!canApply || template.publishedVersion === null}
            />
          </CardFooter>
        </Card>
      ))}
    </div>
  );
}

export function TemplatesGallerySkeleton() {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3" aria-busy="true">
      <Skeleton className="h-44 rounded-xl" />
      <Skeleton className="h-44 rounded-xl" />
      <Skeleton className="h-44 rounded-xl" />
    </div>
  );
}
// #endregion recipe:templates-gallery
