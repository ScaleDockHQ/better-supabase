import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { loadApiKey } from "../api-keys-queries";
import { RotateKeyButton } from "./rotate-key-button";

/** Render inside `<Suspense>`: reads the `id` param and the key. */
export async function ApiKeyDetail({ id }: { id: string }) {
  const [key, permissions, t, format] = await Promise.all([
    loadApiKey(id),
    getPermissions(),
    getExtracted("apiKeys"),
    getFormatter(),
  ]);

  if (key === undefined || key === null) {
    notFound();
  }

  const date = (value: string | undefined) =>
    value === undefined
      ? undefined
      : format.dateTime(new Date(value), { dateStyle: "medium" });

  const live = key.state === "active" || key.state === "grace";

  return (
    <RecordDetailFrame
      title={key.name}
      description={key.token}
      status={
        <Badge
          variant={
            key.state === "active"
              ? "success-light"
              : key.state === "grace"
                ? "warning-light"
                : "secondary"
          }
        >
          {key.state}
        </Badge>
      }
      aside={
        <PropertiesRail
          title={t("Properties")}
          properties={[
            {
              label: t("Acts as"),
              value: key.personal ? t("A person") : t("The organization"),
            },
            { label: t("Kind"), value: key.kind },
            { label: t("Created"), value: date(key.createdAt) },
            { label: t("Last used"), value: date(key.lastUsedAt) },
            { label: t("Expires"), value: date(key.expiresAt) },
            {
              label: t("Rate limit"),
              value:
                key.rateLimit === undefined
                  ? undefined
                  : t("{count, number} per minute", { count: key.rateLimit }),
            },
          ]}
        />
      }
    >
      <Card>
        <CardHeader>
          <CardTitle>{t("Scopes")}</CardTitle>
          <CardDescription>
            {t("What the key may do when it calls the API.")}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          {key.scopes.length === 0 ? (
            <span className="text-sm text-muted-foreground">
              {t("The key has the permissions of its owner.")}
            </span>
          ) : (
            key.scopes.map((scope) => (
              <Badge key={scope} variant="outline">
                {scope}
              </Badge>
            ))
          )}
        </CardContent>
      </Card>
      {key.graceEndsAt === undefined ? null : (
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Rotation in progress")}</CardTitle>
            <CardDescription>
              {t("The old token stops working on {date}.", {
                date: date(key.graceEndsAt) ?? "",
              })}
              {key.successorId === undefined ? null : (
                <>
                  {" "}
                  <Link
                    href={`/settings/api-keys/${key.successorId}`}
                    className="underline"
                  >
                    {t("Open the new key")}
                  </Link>
                </>
              )}
            </CardDescription>
          </CardHeader>
        </Card>
      )}
      {live && can(permissions, "api_keys.manage") ? (
        <Card>
          <CardHeader>
            <CardTitle>{t("Rotate")}</CardTitle>
            <CardDescription>
              {t("Issue a new key and retire this one.")}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <RotateKeyButton id={key.id} />
          </CardContent>
        </Card>
      ) : null}
    </RecordDetailFrame>
  );
}

export function ApiKeyDetailSkeleton() {
  return (
    <div className="grid items-start gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-4 lg:col-span-2">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-48 w-full" />
      </div>
      <Skeleton className="h-48 w-full" />
    </div>
  );
}
