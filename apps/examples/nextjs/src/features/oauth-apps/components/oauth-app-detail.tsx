import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";

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
import { Fact } from "@/features/admin-lists/admin-detail-page";

import { getOAuthApp } from "../oauth-apps-detail-queries";

/** Render inside `<Suspense>`; the fallback is `OAuthAppDetailSkeleton`. */
export async function OAuthAppDetail({ id }: { id: string }) {
  const [app, t, format] = await Promise.all([
    getOAuthApp(id),
    getExtracted("oauthApps"),
    getFormatter(),
  ]);

  if (app === "forbidden") {
    forbidden();
  }

  if (!app) {
    notFound();
  }

  return (
    <RecordDetailFrame
      title={app.name}
      description={app.uri ?? undefined}
      status={
        <Badge variant="info-light">
          {app.type === "public" ? t("Public") : t("Confidential")}
        </Badge>
      }
    >
      <Card>
        <CardHeader>
          <CardTitle>{t("Client")}</CardTitle>
          <CardDescription>
            {t("How this app registered with the OAuth server and signs in.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <dl className="grid gap-4 sm:grid-cols-2">
            <Fact label={t("Registration")}>
              {app.registration === "dynamic" ? t("Dynamic") : t("Manual")}
            </Fact>
            <Fact label={t("Client authentication")}>{app.authMethod}</Fact>
            <Fact label={t("Client ID")}>
              <span className="font-mono text-xs">{app.id}</span>
            </Fact>
            <Fact label={t("Created")}>
              {format.dateTime(new Date(app.createdAt), {
                dateStyle: "medium",
                timeStyle: "short",
              })}
            </Fact>
          </dl>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Redirect URIs")}</CardTitle>
        </CardHeader>
        <CardContent>
          <ul className="flex flex-col gap-1">
            {app.redirectUris.map((uri) => (
              <li key={uri} className="font-mono text-xs break-all">
                {uri}
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Grant types")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-1">
          {app.grantTypes.map((grant) => (
            <Badge key={grant} variant="outline">
              {grant}
            </Badge>
          ))}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function OAuthAppDetailSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
