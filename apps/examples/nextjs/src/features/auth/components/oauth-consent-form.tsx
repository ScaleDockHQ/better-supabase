"use client";

import { useOAuthConsent } from "better-supabase/blocks/sessions/react";
import { useExtracted } from "next-intl";
import { useSyncExternalStore } from "react";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

const noSubscription = (): (() => void) => () => undefined;

const authorizationIdOf = (): string | null =>
  new URLSearchParams(window.location.search).get("authorization_id");

const onServer = (): undefined => undefined;

const leave = (url: string): void => {
  window.location.replace(url);
};

/**
 * The page Supabase Auth's OAuth server sends users to
 * (`[auth.oauth_server] authorization_url_path`). The proxy has already sent
 * a signed-out visitor to sign-in with this URL as `next`. The browser only
 * ever leaves for a `redirect_url` that Auth returned.
 */
export function OAuthConsentForm() {
  const t = useExtracted("oauth");

  const authorizationId = useSyncExternalStore(
    noSubscription,
    authorizationIdOf,
    onServer,
  );

  const { request, deciding, error, approve, deny } = useOAuthConsent({
    authorizationId: authorizationId ?? undefined,
    redirect: leave,
  });

  const load =
    authorizationId === null
      ? {
          kind: "failed" as const,
          message: t(
            "This link has no authorization request. Start again from the app that sent you here.",
          ),
        }
      : request === undefined && error !== undefined
        ? { kind: "failed" as const, message: error.message }
        : request === undefined
          ? { kind: "loading" as const }
          : { kind: "ready" as const, details: request };

  if (load.kind === "loading") {
    return (
      <Card>
        <CardHeader className="text-center">
          <Skeleton className="mx-auto h-6 w-48" />
          <Skeleton className="mx-auto h-4 w-56" />
        </CardHeader>
        <CardContent>
          <Skeleton className="h-16 w-full" />
        </CardContent>
      </Card>
    );
  }

  if (load.kind === "failed") {
    return (
      <Card>
        <CardHeader className="text-center">
          <CardTitle className="text-xl">
            {t("This request can't continue")}
          </CardTitle>
          <CardDescription data-testid="oauth-consent-error">
            {load.message}
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  const { details } = load;
  const { scopes } = details;

  return (
    <Card>
      <CardHeader className="text-center">
        <CardTitle className="text-xl">
          {t("Connect {client}", { client: details.client.name })}
        </CardTitle>
        <CardDescription>
          {t("{client} wants to act as {email} in Acme Cloud.", {
            client: details.client.name,
            email: details.user.email,
          })}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4 text-sm">
        <div>
          <p className="font-medium">{t("It asks for")}</p>
          {scopes.length > 0 ? (
            <ul className="mt-1 list-disc ps-5 text-muted-foreground">
              {scopes.map((scope) => (
                <li key={scope}>
                  <code>{scope}</code>
                </li>
              ))}
            </ul>
          ) : (
            <p className="mt-1 text-muted-foreground">
              {t("Access to your account, with your permissions.")}
            </p>
          )}
        </div>
        <p className="text-muted-foreground">
          {t(
            "Row Level Security still applies: it can only see and change what you can. After you approve, you return to {host}.",
            { host: details.redirectHost },
          )}
        </p>
        {error ? <p className="text-destructive">{error.message}</p> : null}
      </CardContent>
      <CardFooter className="flex gap-2">
        <Button
          variant="outline"
          className="flex-1"
          disabled={deciding !== undefined}
          onClick={() => {
            void deny();
          }}
        >
          {t("Deny")}
        </Button>
        <Button
          className="flex-1"
          disabled={deciding !== undefined}
          onClick={() => {
            void approve();
          }}
        >
          {t("Approve")}
        </Button>
      </CardFooter>
    </Card>
  );
}
