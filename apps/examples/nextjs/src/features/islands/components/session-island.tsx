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

import { getIslandSession } from "../islands-queries";

export type SessionFact =
  | "email"
  | "organization"
  | "expires"
  | "issued"
  | "version";

/**
 * Render inside `<Suspense>`: one fact from the verified session. Ten islands
 * read the session; the token still verifies once for the request.
 */
export async function SessionIsland({ fact }: { fact: SessionFact }) {
  const [session, t, format] = await Promise.all([
    getIslandSession(),
    getExtracted("islands"),
    getFormatter(),
  ]);

  if (!session) {
    return null;
  }

  const time = (seconds: number | null) =>
    seconds === null
      ? null
      : format.dateTime(new Date(seconds * 1000), {
          timeStyle: "short",
          dateStyle: "medium",
        });

  const facts: Record<SessionFact, { title: string; value: string | null }> = {
    email: { title: t("Signed in as"), value: session.email },
    organization: { title: t("Organization"), value: session.organizationId },
    expires: { title: t("Token expires"), value: time(session.expiresAt) },
    issued: { title: t("Token issued"), value: time(session.issuedAt) },
    version: {
      title: t("Authorization version"),
      value:
        session.authzVersion === null
          ? null
          : format.number(session.authzVersion),
    },
  };

  const { title, value } = facts[fact];

  return (
    <Card data-testid={`island-${fact}`}>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{t("From the verified token")}</CardDescription>
      </CardHeader>
      <CardContent>
        {value === null ? (
          <Badge variant="secondary">{t("Not in the token")}</Badge>
        ) : (
          <span className="text-sm font-medium break-all">{value}</span>
        )}
      </CardContent>
    </Card>
  );
}

export function SessionIslandSkeleton() {
  return <Skeleton className="h-36 rounded-xl" aria-busy="true" />;
}
