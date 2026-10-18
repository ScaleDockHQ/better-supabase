import { ListPlusIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";
import * as v from "valibot";

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
  CardAction,
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

import { retryCustomFields } from "../custom-fields-actions";
import { getFields } from "../custom-fields-queries";
import { FieldEntitySchema } from "../custom-fields-types";
import {
  EntityPicker,
  FieldDialog,
  FieldRowControls,
} from "./custom-field-controls";
import { FieldTypeBadge } from "./field-type-badge";

// #region recipe:custom-fields-editor
/**
 * Render inside `<Suspense>`: the custom fields of the record type in
 * `?entity=`, in display order. Managers add, relabel, reorder and delete
 * them.
 */
export async function CustomFieldsEditor({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [session, t, params] = await Promise.all([
    getSession(),
    getExtracted("custom-fields"),
    searchParams,
  ]);

  if (!can(session, "custom_fields.read")) {
    forbidden();
  }

  const parsed = v.safeParse(FieldEntitySchema, params["entity"]);
  const entity = parsed.success ? parsed.output : "customer";
  const fields = await getFields(entity);

  if (fields.kind === "no-organization") {
    return null;
  }

  const canManage = can(session, "custom_fields.manage");

  return (
    <Card data-recipe="custom-fields-editor">
      <CardHeader>
        <CardTitle>{t("Custom fields")}</CardTitle>
        <CardDescription>
          {t("Extra fields on your records, shown in this order.")}
        </CardDescription>
        <CardAction>
          <div className="flex items-center gap-2">
            <EntityPicker entity={entity} />
            {canManage && fields.kind === "ok" && fields.data.length > 0 ? (
              <FieldDialog key={entity} entity={entity} />
            ) : null}
          </div>
        </CardAction>
      </CardHeader>
      <CardContent>
        {fields.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The fields didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retryCustomFields}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : fields.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ListPlusIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No custom fields yet")}</EmptyTitle>
              <EmptyDescription>
                {canManage
                  ? t(
                      "Add a field to record what your team tracks on top of the built-in ones.",
                    )
                  : t("An admin can add fields for this record type.")}
              </EmptyDescription>
            </EmptyHeader>
            {canManage ? (
              <EmptyContent>
                <FieldDialog key={entity} entity={entity} />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Label")}</TableHead>
                <TableHead>{t("Key")}</TableHead>
                <TableHead>{t("Type")}</TableHead>
                {canManage ? (
                  <TableHead className="text-right">{t("Actions")}</TableHead>
                ) : null}
              </TableRow>
            </TableHeader>
            <TableBody>
              {fields.data.map((field, index) => (
                <TableRow key={field.id}>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{field.label}</span>
                      {field.sensitive ? (
                        <Badge variant="warning-light">{t("Sensitive")}</Badge>
                      ) : null}
                    </div>
                  </TableCell>
                  <TableCell className="font-mono text-xs text-muted-foreground">
                    {field.key}
                  </TableCell>
                  <TableCell>
                    <FieldTypeBadge type={field.type} />
                  </TableCell>
                  {canManage ? (
                    <TableCell>
                      <FieldRowControls
                        entity={entity}
                        field={field}
                        first={index === 0}
                        last={index === fields.data.length - 1}
                      />
                    </TableCell>
                  ) : null}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:custom-fields-editor

export function CustomFieldsEditorSkeleton() {
  return <Skeleton className="h-80 rounded-xl" aria-busy="true" />;
}
