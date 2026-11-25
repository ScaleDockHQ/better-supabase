import { KeyRoundIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";
import { forbidden, unstable_rethrow } from "next/navigation";

import { KpiBand } from "@/components/record-list/kpi-band";
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
  CardAction,
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
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import type { SigningKeysOverview } from "../signing-keys-queries";

import { getSigningKeys } from "../signing-keys-queries";
import { SIGNING_KEYS_PERMISSION } from "../signing-keys-server";
import { RotateSigningKeyButton } from "./rotate-signing-key-button";

// #region recipe:signing-keys-rotation
type SigningKeysState =
  | { readonly kind: "ok"; readonly overview: SigningKeysOverview }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

async function getSigningKeysState(): Promise<SigningKeysState> {
  try {
    const overview = await getSigningKeys();

    return overview ? { kind: "ok", overview } : { kind: "no-organization" };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>`: the organization's active signing key and the
 * retired ones still published, with a rotate button. The keys are service-role
 * only, so this checks `organization.update` before it reads.
 */
export async function SigningKeysRotation() {
  const [t, permissions] = await Promise.all([
    getExtracted("signingKeys"),
    getPermissions(),
  ]);

  if (!can(permissions, SIGNING_KEYS_PERMISSION)) {
    forbidden();
  }

  const state = await getSigningKeysState();

  if (state.kind === "no-organization") {
    return null;
  }

  const rows =
    state.kind === "ok"
      ? [
          ...(state.overview.active
            ? [{ ...state.overview.active, active: true }]
            : []),
          ...state.overview.previous.map((key) => ({ ...key, active: false })),
        ]
      : [];

  return (
    <div className="flex flex-col gap-6">
      {state.kind === "ok" ? (
        <KpiBand
          kpis={[
            {
              label: t("Active key"),
              value: state.overview.active ? t("Yes") : t("None"),
              hint: state.overview.active?.algorithm ?? t("No signing key yet"),
            },
            {
              label: t("Previous keys"),
              value: String(state.overview.previous.length),
              hint: t("Published until the tokens they signed expire."),
            },
            { label: t("Published keys"), value: String(rows.length) },
          ]}
        />
      ) : null}
      <Card data-recipe="signing-keys-rotation">
        <CardHeader>
          <CardTitle>{t("Signing keys")}</CardTitle>
          <CardDescription>
            {t(
              "The keys that sign this organization's tokens. Private keys stay in Vault; receivers check signatures against the published JWKS.",
            )}
          </CardDescription>
          {rows.length > 0 ? (
            <CardAction>
              <RotateSigningKeyButton first={false} />
            </CardAction>
          ) : null}
        </CardHeader>
        <CardContent>
          {state.kind === "error" ? (
            <Alert variant="destructive">
              <TriangleAlertIcon />
              <AlertTitle>{t("The signing keys didn't load")}</AlertTitle>
              <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
              <AlertAction>
                <form action={retry}>
                  <Button size="sm" variant="outline" type="submit">
                    {t("Retry")}
                  </Button>
                </form>
              </AlertAction>
            </Alert>
          ) : (
            <div className="flex flex-col gap-3">
              {rows.length === 0 ? (
                <Empty className="border">
                  <EmptyHeader>
                    <EmptyMedia variant="icon">
                      <KeyRoundIcon />
                    </EmptyMedia>
                    <EmptyTitle>{t("No signing key yet")}</EmptyTitle>
                    <EmptyDescription>
                      {t(
                        "Create one before the organization signs any tokens.",
                      )}
                    </EmptyDescription>
                  </EmptyHeader>
                  <EmptyContent>
                    <RotateSigningKeyButton first />
                  </EmptyContent>
                </Empty>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t("Key ID")}</TableHead>
                      <TableHead>{t("Algorithm")}</TableHead>
                      <TableHead>{t("Status")}</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((key) => (
                      <TableRow key={key.kid}>
                        <TableCell className="font-mono text-xs">
                          {key.kid}
                        </TableCell>
                        <TableCell className="text-sm">
                          {key.algorithm}
                        </TableCell>
                        <TableCell>
                          {key.active ? (
                            <Badge variant="success-light">{t("Active")}</Badge>
                          ) : (
                            <Badge variant="secondary">{t("Previous")}</Badge>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
              <p className="text-xs text-muted-foreground">
                {t("Receivers read the public keys at")}{" "}
                <a
                  href={state.overview.jwksPath}
                  className="font-mono underline underline-offset-4 transition-colors hover:text-foreground"
                >
                  {state.overview.jwksPath}
                </a>
              </p>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

export function SigningKeysRotationSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
// #endregion recipe:signing-keys-rotation
