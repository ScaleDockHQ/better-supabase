import { getExtracted, getFormatter } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

import type { Islands, IslandScope } from "../islands-queries";

import { getIslandsIn } from "../islands-queries";
import { IslandError } from "./island-error";

export type SessionFact =
  | "email"
  | "organization"
  | "expires"
  | "issued"
  | "version";

/**
 * Render inside `<Suspense>`: one fact from the bootstrap result. The version
 * is the one the database saw in the token, so it moves after a refresh.
 */
export async function SessionIsland({
  fact,
  scope,
}: {
  fact: SessionFact;
  scope: Promise<IslandScope>;
}) {
  const [t, format] = await Promise.all([
    getExtracted("islands"),
    getFormatter(),
  ]);

  const titles: Record<SessionFact, string> = {
    email: t("Signed in as"),
    organization: t("Organization"),
    expires: t("Token expires"),
    issued: t("Token issued"),
    version: t("Authorization version"),
  };

  let islands: Islands;

  try {
    islands = await getIslandsIn(await scope);
  } catch {
    return <IslandError title={titles[fact]} />;
  }

  if (islands.userId === null) {
    return null;
  }

  const time = (seconds: number | null) =>
    seconds === null
      ? null
      : format.dateTime(new Date(seconds * 1000), {
          timeStyle: "short",
          dateStyle: "medium",
        });

  const values: Record<SessionFact, string | null> = {
    email: islands.email,
    organization: islands.organizationId,
    expires: time(islands.expiresAt),
    issued: time(islands.issuedAt),
    version:
      islands.authzVersion === null
        ? null
        : format.number(islands.authzVersion),
  };

  const value = values[fact];

  return (
    <Card data-testid={`island-${fact}`}>
      <CardHeader>
        <CardTitle>{titles[fact]}</CardTitle>
        <CardDescription>{t("From the verified token")}</CardDescription>
      </CardHeader>
      <CardContent>
        {value === null ? (
          <Badge variant="secondary">{t("Not in the token")}</Badge>
        ) : (
          <span
            className="text-sm font-medium break-all tabular-nums"
            data-testid={`island-${fact}-value`}
          >
            {value}
          </span>
        )}
      </CardContent>
    </Card>
  );
}

export function SessionIslandSkeleton() {
  return <Skeleton className="h-36 rounded-xl" aria-busy="true" />;
}
