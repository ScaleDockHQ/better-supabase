import { ShareIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";

import { getPortal } from "../portal-queries";

/**
 * Render inside `<Suspense>`: what the signed-in guest may read. A guest has no
 * membership, only grants on single records, so the portal lists those.
 */
export async function GuestPortal() {
  const [t, portal] = await Promise.all([getExtracted("portal"), getPortal()]);

  if (portal.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The portal didn't load")}</AlertTitle>
        <AlertDescription>
          {t("Reload the page to try again.")}
        </AlertDescription>
      </Alert>
    );
  }

  const grants = portal.memberships.flatMap((membership) =>
    membership.grants.map((grant) => ({ membership, grant })),
  );

  if (grants.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <ShareIcon />
          </EmptyMedia>
          <EmptyTitle>{t("Nothing is shared with you yet")}</EmptyTitle>
          <EmptyDescription>
            {t("Records an organization shares with you appear here.")}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  return (
    <div className="grid gap-4">
      {grants.map(({ membership, grant }) => (
        <Card key={grant.id} size="sm">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              {grant.subjectType}
              {grant.actions.map((action) => (
                <Badge key={action} variant="secondary">
                  {action}
                </Badge>
              ))}
            </CardTitle>
          </CardHeader>
          <CardContent className="grid gap-1 text-sm text-muted-foreground">
            <span>{grant.subjectId}</span>
            <span>{membership.organizationId}</span>
            {grant.expiresAt ? (
              <span>{t("Until {date}", { date: grant.expiresAt })}</span>
            ) : null}
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

export function GuestPortalSkeleton() {
  return (
    <div className="grid gap-4" aria-busy="true">
      <Skeleton className="h-24 rounded-xl" />
      <Skeleton className="h-24 rounded-xl" />
    </div>
  );
}
