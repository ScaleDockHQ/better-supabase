import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
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
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

import { getIdentities } from "../identities-queries";
import { LinkChatForm, UnlinkButton } from "./identity-controls";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: the user's linked email and chat identities. */
export async function IdentitiesCard() {
  const [result, t] = await Promise.all([
    getIdentities().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getExtracted("identities"),
  ]);

  if (!result.ok) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("Your linked accounts didn't load")}</AlertTitle>
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

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Linked accounts")}</CardTitle>
        <CardDescription>
          {t(
            "The email addresses and chat accounts that act as you. A chat account links only with a code you issue here.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-4">
        {result.data.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("No accounts linked yet.")}
          </p>
        ) : (
          <ul className="grid gap-2">
            {result.data.map((identity) => (
              <li
                key={identity.id}
                className="flex items-center justify-between gap-2 text-sm"
              >
                <span className="flex items-center gap-2">
                  {identity.value}
                  <Badge variant="secondary">
                    {identity.provider ?? identity.kind}
                  </Badge>
                </span>
                {identity.source === "link" ? (
                  <UnlinkButton id={identity.id} />
                ) : null}
              </li>
            ))}
          </ul>
        )}
        <LinkChatForm />
      </CardContent>
    </Card>
  );
}

export function IdentitiesCardSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
