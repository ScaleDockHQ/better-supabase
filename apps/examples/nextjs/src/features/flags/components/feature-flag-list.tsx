// #region recipe:feature-flag-toggles
import { tenantOf } from "better-supabase/next";
import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";
import { unstable_rethrow } from "next/navigation";

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
import { bsb } from "@/lib/supabase/server";

/** The flags `src/flags.ts` defines. */
const FLAG_KEYS = ["beta-page", "pricing-banner"] as const;

type FlagKey = (typeof FLAG_KEYS)[number];

interface FlagValue {
  readonly key: FlagKey;
  readonly on: boolean;
}

type FlagValues =
  | { readonly kind: "ok"; readonly flags: readonly FlagValue[] }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * Each flag as `flag_enabled` answers it for the active organization, with its
 * rules and overrides. Changing a flag is for platform staff (`flags.manage`),
 * so the list only reads. A failed read throws, so it is never cached and Retry
 * reads again.
 */
async function loadFlags(): Promise<readonly FlagValue[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  return Promise.all(
    FLAG_KEYS.map(async (key) => ({
      key,
      on: (await db.$api("flag_enabled", { key, tenant }).orThrow()) === true,
    })),
  );
}

async function loadFlagValues(): Promise<FlagValues> {
  try {
    const flags = await loadFlags();

    return flags ? { kind: "ok", flags } : { kind: "no-organization" };
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

/** Render inside `<Suspense>`: the flags that are on for this organization. */
export async function FeatureFlagList() {
  const [values, t] = await Promise.all([
    loadFlagValues(),
    getExtracted("flags"),
  ]);

  if (values.kind === "no-organization") {
    return null;
  }

  const labels: Record<FlagKey, string> = {
    "beta-page": t("The beta page and its menu entry"),
    "pricing-banner": t("The upgrade banner on the pricing page"),
  };

  return (
    <Card data-testid="flags" data-recipe="feature-flag-toggles">
      <CardHeader>
        <CardTitle>{t("Feature flags")}</CardTitle>
        <CardDescription>
          {t(
            "What's turned on for this organization. Support changes these for you.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {values.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The flags didn't load")}</AlertTitle>
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
          <ul className="flex flex-col divide-y">
            {values.flags.map((flag) => (
              <li
                key={flag.key}
                data-testid={`feature-flag-${flag.key}`}
                className="flex items-center justify-between gap-3 py-3 first:pt-0 last:pb-0"
              >
                <div className="flex flex-col gap-1">
                  <span className="font-mono text-sm">{flag.key}</span>
                  <span className="text-xs text-muted-foreground">
                    {labels[flag.key]}
                  </span>
                </div>
                {flag.on ? (
                  <Badge variant="success-light">{t("On")}</Badge>
                ) : (
                  <Badge variant="secondary">{t("Off")}</Badge>
                )}
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

export function FeatureFlagListSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
// #endregion recipe:feature-flag-toggles
