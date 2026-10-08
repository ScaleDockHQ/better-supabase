"use client";

import type {
  AuthOAuthAuthorizationDetailsResponse,
  OAuthAuthorizationDetails,
} from "@supabase/supabase-js";

import { useExtracted } from "next-intl";
import { useEffect, useState, useTransition } from "react";

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
import { useSupabase } from "@/lib/hooks";

type Load =
  | { readonly kind: "loading" }
  | { readonly kind: "ready"; readonly details: OAuthAuthorizationDetails }
  | { readonly kind: "failed"; readonly message: string };

// A request the user consented to before is used up by the first read, so a
// second effect run (Strict Mode) has to share it.
const reads = new Map<string, Promise<AuthOAuthAuthorizationDetailsResponse>>();

const hostOf = (url: string): string => {
  try {
    return new URL(url).host;
  } catch {
    return url;
  }
};

/**
 * The page Supabase Auth's OAuth server sends users to
 * (`[auth.oauth_server] authorization_url_path`). The proxy has already sent
 * a signed-out visitor to sign-in with this URL as `next`. The browser only
 * ever leaves for a `redirect_url` that Auth returned.
 */
export function OAuthConsentForm() {
  const t = useExtracted("oauth");
  const supabase = useSupabase();
  const [load, setLoad] = useState<Load>({ kind: "loading" });
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  useEffect(() => {
    let active = true;
    const id = new URLSearchParams(window.location.search).get(
      "authorization_id",
    );
    let read = id ? reads.get(id) : Promise.resolve(null);
    if (id && !read) {
      read = supabase.auth.oauth.getAuthorizationDetails(id);
      reads.set(id, read);
    }
    void read?.then((result) => {
      if (!active) return;
      if (!result) {
        setLoad({
          kind: "failed",
          message: t(
            "This link has no authorization request. Start again from the app that sent you here.",
          ),
        });
        return;
      }
      if (result.error) {
        setLoad({ kind: "failed", message: result.error.message });
        return;
      }
      // Consent given before: Auth answers with the client's redirect.
      if (!("authorization_id" in result.data)) {
        window.location.replace(result.data.redirect_url);
        return;
      }
      setLoad({ kind: "ready", details: result.data });
    });
    return () => {
      active = false;
    };
  }, [supabase, t]);

  const decide = (details: OAuthAuthorizationDetails, approve: boolean) => {
    startTransition(async () => {
      setError(null);
      const options = { skipBrowserRedirect: true };
      const result = approve
        ? await supabase.auth.oauth.approveAuthorization(
            details.authorization_id,
            options,
          )
        : await supabase.auth.oauth.denyAuthorization(
            details.authorization_id,
            options,
          );
      if (result.error) {
        setError(result.error.message);
        return;
      }
      window.location.assign(result.data.redirect_url);
      // Keeps the buttons disabled while the browser leaves.
      await new Promise<never>(() => {});
    });
  };

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
  const scopes = details.scope.split(" ").filter(Boolean);
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
            <ul className="text-muted-foreground mt-1 list-disc ps-5">
              {scopes.map((scope) => (
                <li key={scope}>
                  <code>{scope}</code>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-muted-foreground mt-1">
              {t("Access to your account, with your permissions.")}
            </p>
          )}
        </div>
        <p className="text-muted-foreground">
          {t(
            "Row Level Security still applies: it can only see and change what you can. After you approve, you return to {host}.",
            { host: hostOf(details.redirect_uri) },
          )}
        </p>
        {error ? <p className="text-destructive">{error}</p> : null}
      </CardContent>
      <CardFooter className="flex gap-2">
        <Button
          variant="outline"
          className="flex-1"
          disabled={pending}
          onClick={() => {
            decide(details, false);
          }}
        >
          {t("Deny")}
        </Button>
        <Button
          className="flex-1"
          disabled={pending}
          onClick={() => {
            decide(details, true);
          }}
        >
          {t("Approve")}
        </Button>
      </CardFooter>
    </Card>
  );
}
