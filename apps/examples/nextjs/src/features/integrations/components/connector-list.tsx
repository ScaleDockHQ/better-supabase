import { PlugIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
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
import { Link } from "@/i18n/navigation";

import { getConnectors } from "../integrations-connectors";

/** Render inside `<Suspense>`; the fallback is `ConnectorListSkeleton`. */
export async function ConnectorList() {
  const [connectors, t] = await Promise.all([
    getConnectors(),
    getExtracted("integrations"),
  ]);

  if (connectors === null) {
    return null;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Connectors")}</CardTitle>
        <CardDescription>
          {t("The MCP servers the organization's agents can call.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {connectors.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <PlugIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No connectors yet")}</EmptyTitle>
              <EmptyDescription>
                {t("Register an MCP server to let agents call its tools.")}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <ul className="flex flex-col divide-y">
            {connectors.map((connector) => (
              <li
                key={connector.id}
                className="flex items-center justify-between gap-3 py-2"
              >
                <div className="flex min-w-0 flex-col">
                  <Link
                    href={`/settings/integrations/${connector.id}`}
                    prefetch
                    className="truncate text-sm font-medium hover:underline"
                  >
                    {connector.name}
                  </Link>
                  <span className="truncate text-xs text-muted-foreground">
                    {connector.url}
                  </span>
                </div>
                <Badge
                  variant={connector.enabled ? "success-light" : "secondary"}
                >
                  {connector.enabled ? t("Enabled") : t("Disabled")}
                </Badge>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

export function ConnectorListSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
