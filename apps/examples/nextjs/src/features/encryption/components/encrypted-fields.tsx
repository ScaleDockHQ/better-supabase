import { LockKeyholeIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";

import type { FieldEntity } from "@/features/custom-fields/custom-fields-types";

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
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { getEncryptionView } from "../encryption-queries";
import { RotateKeyButton } from "./rotate-key-button";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>` and a `PermissionGate` for `custom_fields.read`:
 * the organization's key status from the field-encryption block and the fields
 * it seals with that key. Members with `field_encryption.manage` rotate the
 * key.
 */
export async function EncryptedFields() {
  const [result, t, format, permissions] = await Promise.all([
    getEncryptionView().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getExtracted("encryption"),
    getFormatter(),
    getPermissions(),
  ]);

  if (!result.ok) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The encrypted fields didn't load")}</AlertTitle>
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

  const view = result.data;

  if (view === null) {
    return null;
  }

  const when = (iso: string | undefined): string =>
    iso === undefined
      ? t("Never")
      : format.dateTime(new Date(iso), {
          dateStyle: "medium",
          timeStyle: "short",
        });

  const entityLabel = (entity: FieldEntity): string => {
    switch (entity) {
      case "customer": {
        return t("Customer");
      }

      case "work_item": {
        return t("Work item");
      }

      default: {
        const never: never = entity;

        return never;
      }
    }
  };

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <CardTitle>{t("Data key")}</CardTitle>
          <CardDescription>
            {t(
              "Values of sensitive fields and encrypted columns are encrypted at rest with a key kept in Supabase Vault. Only the functions that check your access decrypt them.",
            )}
          </CardDescription>
          {view.key !== undefined &&
          can(permissions, "field_encryption.manage") ? (
            <CardAction>
              <RotateKeyButton />
            </CardAction>
          ) : null}
        </CardHeader>
        <CardContent className="grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-3">
          <div className="flex flex-col gap-1">
            <span className="text-xs text-muted-foreground">
              {t("Key owner")}
            </span>
            <span className="font-mono text-xs">{view.keyOwner}</span>
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-xs text-muted-foreground">
              {t("Created")}
            </span>
            {view.key === undefined ? (
              <span>
                <Badge variant="secondary">{t("No key yet")}</Badge>
              </span>
            ) : (
              <span className="tabular-nums">{when(view.key.createdAt)}</span>
            )}
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-xs text-muted-foreground">
              {t("Last rotated")}
            </span>
            <span className="tabular-nums">{when(view.key?.rotatedAt)}</span>
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-xs text-muted-foreground">
              {t("Lookup key")}
            </span>
            <span className="tabular-nums">
              {view.lookupKey === undefined
                ? t("None")
                : when(view.lookupKey.createdAt)}
            </span>
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-xs text-muted-foreground">
              {t("Encrypted columns")}
            </span>
            <span>
              {view.columns.length === 0
                ? t("None")
                : view.columns
                    .map((column) => `${column.table}.${column.column}`)
                    .join(", ")}
            </span>
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-xs text-muted-foreground">
              {t("Stored as plain values")}
            </span>
            <span>{t("{count} fields", { count: String(view.plain) })}</span>
          </div>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Encrypted fields")}</CardTitle>
          <CardDescription>
            {t("Custom fields marked sensitive, on every record type.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {view.fields.length === 0 ? (
            <Empty className="border">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <LockKeyholeIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No encrypted fields")}</EmptyTitle>
                <EmptyDescription>
                  {t("Mark a custom field as sensitive to encrypt its values.")}
                </EmptyDescription>
              </EmptyHeader>
              <EmptyContent>
                <Link
                  href="/settings/custom-fields"
                  className={buttonVariants({ variant: "outline", size: "sm" })}
                >
                  {t("Open custom fields")}
                </Link>
              </EmptyContent>
            </Empty>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Field")}</TableHead>
                  <TableHead>{t("Record type")}</TableHead>
                  <TableHead>{t("Type")}</TableHead>
                  <TableHead>{t("State")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {view.fields.map((field) => (
                  <TableRow key={field.id}>
                    <TableCell className="font-medium">{field.label}</TableCell>
                    <TableCell>{entityLabel(field.entity)}</TableCell>
                    <TableCell className="font-mono text-xs">
                      {field.type}
                    </TableCell>
                    <TableCell>
                      <Badge variant="success-light">{t("Encrypted")}</Badge>
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

export function EncryptedFieldsSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
