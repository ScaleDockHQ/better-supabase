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

import { getConnector } from "../integrations-connectors";

/** Render inside `<Suspense>`; the fallback is `ConnectorDetailSkeleton`. */
export async function ConnectorDetail({ id }: { id: string }) {
  const [connector, t, format] = await Promise.all([
    getConnector(id),
    getExtracted("integrations"),
    getFormatter(),
  ]);

  if (connector === "forbidden") {
    forbidden();
  }

  if (!connector) {
    notFound();
  }

  return (
    <RecordDetailFrame
      title={connector.name}
      description={connector.url}
      status={
        <Badge variant={connector.enabled ? "success-light" : "secondary"}>
          {connector.enabled ? t("Enabled") : t("Disabled")}
        </Badge>
      }
    >
      <Card>
        <CardHeader>
          <CardTitle>{t("Server")}</CardTitle>
          <CardDescription>
            {t("How agents reach this MCP server and sign in to it.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <dl className="grid gap-4 sm:grid-cols-2">
            <Fact label={t("Transport")}>{connector.transport}</Fact>
            <Fact label={t("Authentication")}>{connector.authType}</Fact>
            <Fact label={t("Active grants")}>{connector.grants}</Fact>
            <Fact label={t("Created")}>
              {format.dateTime(new Date(connector.createdAt), {
                dateStyle: "medium",
                timeStyle: "short",
              })}
            </Fact>
          </dl>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Scopes")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-1">
          {connector.scopes.length === 0 ? (
            <span className="text-sm text-muted-foreground">
              {t("This connector asks for no scopes.")}
            </span>
          ) : (
            connector.scopes.map((scope) => (
              <Badge key={scope} variant="outline">
                {scope}
              </Badge>
            ))
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function ConnectorDetailSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
