import { KeyRoundIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";
import { forbidden, unstable_rethrow } from "next/navigation";

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
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import type { SigningKeysOverview } from "../signing-keys-queries";

import { loadSigningKeys } from "../signing-keys-queries";
import { SIGNING_KEYS_PERMISSION } from "../signing-keys-server";
import { RotateSigningKeyButton } from "./rotate-signing-key-button";

// #region recipe:signing-keys-rotation
type SigningKeysState =
  | { readonly kind: "ok"; readonly overview: SigningKeysOverview }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

async function loadSigningKeysState(): Promise<SigningKeysState> {
  try {
    const overview = await loadSigningKeys();

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
  const [session, t] = await Promise.all([
    getSession(),
    getExtracted("signingKeys"),
  ]);

  if (!can(session, SIGNING_KEYS_PERMISSION)) {
    forbidden();
  }

  const state = await loadSigningKeysState();

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
        ) : rows.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <KeyRoundIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No signing key yet")}</EmptyTitle>
              <EmptyDescription>
                {t("Create one before the organization signs any tokens.")}
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
                  <TableCell className="font-mono text-xs">{key.kid}</TableCell>
                  <TableCell className="text-sm">{key.algorithm}</TableCell>
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
      </CardContent>
    </Card>
  );
}

export function SigningKeysRotationSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
// #endregion recipe:signing-keys-rotation
