import { GlobeIcon, KeyRoundIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden, unstable_rethrow } from "next/navigation";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { refreshSso } from "../sso-actions";
import { loadSsoSettings, type SsoSettingsData } from "../sso-queries";
import {
  AddDomainForm,
  AddSamlForm,
  DomainActions,
  RemoveConnectionButton,
} from "./sso-controls";

async function loadSettings(): Promise<
  { kind: "ok"; data: SsoSettingsData | null } | { kind: "error" }
> {
  try {
    return { kind: "ok", data: await loadSsoSettings() };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

// #region recipe:sso-settings
/**
 * The organization's email domains (claimed with a TXT record, then
 * verified) and its SAML connection. A verified domain sets the role new
 * users at it join with and whether they must sign in with SSO.
 */
export async function SsoSettings() {
  if (!can(await getSession(), "sso.manage")) {
    forbidden();
  }

  const [t, format, result] = await Promise.all([
    getExtracted("sso"),
    getFormatter(),
    loadSettings(),
  ]);

  if (result.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="sso-settings">
        <TriangleAlertIcon />
        <AlertTitle>{t("SSO settings could not be loaded")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={refreshSso}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  if (result.data === null) {
    return (
      <p className="text-sm text-muted-foreground" data-recipe="sso-settings">
        {t("Pick an organization to manage its single sign-on.")}
      </p>
    );
  }

  const { domains, connections } = result.data;

  const verifiedDomains = domains
    .filter((domain) => domain.verified)
    .map((domain) => domain.domain);

  return (
    <div className="flex flex-col gap-6" data-recipe="sso-settings">
      <Card id="sso-domains">
        <CardHeader>
          <CardTitle>{t("Domains")}</CardTitle>
          <CardDescription>
            {t(
              "Claim the email domains your company owns. Publish the TXT record at your DNS host, then verify the domain.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {domains.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <GlobeIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No domains yet")}</EmptyTitle>
                <EmptyDescription>
                  {t("Add your company's email domain to start.")}
                </EmptyDescription>
              </EmptyHeader>
              <EmptyContent>
                <AddDomainForm />
              </EmptyContent>
            </Empty>
          ) : (
            <>
              <ul className="flex flex-col divide-y rounded-lg border">
                {domains.map((domain) => (
                  <li key={domain.id} className="flex flex-col gap-3 p-3">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium">
                          {domain.domain}
                        </span>
                        {domain.verified ? (
                          <Badge variant="success-light">{t("Verified")}</Badge>
                        ) : (
                          <Badge variant="warning-light">
                            {t("Not verified")}
                          </Badge>
                        )}
                      </div>
                      <DomainActions domain={domain} />
                    </div>
                    {domain.verified ? null : (
                      <dl className="grid gap-1 text-xs text-muted-foreground sm:grid-cols-[auto_1fr] sm:gap-x-3">
                        <dt>{t("TXT name")}</dt>
                        <dd className="font-mono break-all text-foreground">
                          {domain.recordName}
                        </dd>
                        <dt>{t("TXT value")}</dt>
                        <dd className="font-mono break-all text-foreground">
                          {domain.recordValue}
                        </dd>
                      </dl>
                    )}
                  </li>
                ))}
              </ul>
              <AddDomainForm />
            </>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("SAML connection")}</CardTitle>
          <CardDescription>
            {t(
              "Members at your verified domains sign in through your identity provider, such as Okta or Microsoft Entra ID.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {connections.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <KeyRoundIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No SAML connection")}</EmptyTitle>
                <EmptyDescription>
                  {verifiedDomains.length === 0
                    ? t(
                        "Verify a domain first, then connect your identity provider.",
                      )
                    : t(
                        "Connect your identity provider with its metadata URL.",
                      )}
                </EmptyDescription>
              </EmptyHeader>
              <EmptyContent>
                {verifiedDomains.length === 0 ? (
                  <a
                    href="#sso-domains"
                    className={buttonVariants({ variant: "outline" })}
                  >
                    {t("Go to domains")}
                  </a>
                ) : (
                  <AddSamlForm verifiedDomains={verifiedDomains} />
                )}
              </EmptyContent>
            </Empty>
          ) : (
            <ul className="flex flex-col divide-y rounded-lg border">
              {connections.map((connection) => (
                <li
                  key={connection.id}
                  className="flex flex-wrap items-center justify-between gap-2 p-3"
                >
                  <div className="flex min-w-0 flex-col gap-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-sm font-medium">
                        {t("SAML 2.0")}
                      </span>
                      {connection.domains.map((domain) => (
                        <Badge key={domain} variant="outline">
                          {domain}
                        </Badge>
                      ))}
                    </div>
                    <span className="truncate text-xs text-muted-foreground">
                      {connection.metadataUrl ?? t("Metadata uploaded as XML")}
                      {" · "}
                      {t("Added {date}", {
                        date: format.dateTime(new Date(connection.createdAt), {
                          dateStyle: "medium",
                        }),
                      })}
                    </span>
                  </div>
                  <RemoveConnectionButton id={connection.id} />
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
// #endregion recipe:sso-settings

export function SsoSettingsSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-56 rounded-xl" />
      <Skeleton className="h-48 rounded-xl" />
    </div>
  );
}
