// #region recipe:feature-gate
"use client";

import type { ReactNode } from "react";

import { useFeatureGate } from "better-supabase/blocks/entitlements/react";
import { LockIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { Entitlement } from "@/lib/claims";

import { buttonVariants } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

/**
 * Renders `children` only when the active organization's plan includes
 * `feature`, read from the session's `features` claim; otherwise a link to the
 * plans. UX only: RLS and the route behind it check the feature too.
 */
export function FeatureGate({
  feature,
  children,
}: {
  feature: Entitlement;
  children: ReactNode;
}) {
  const t = useExtracted("billing");
  const { allowed } = useFeatureGate(feature);

  if (allowed === undefined) {
    return <Skeleton className="h-8 w-28" aria-busy="true" />;
  }

  if (allowed) {
    return children;
  }

  return (
    <Link
      href="/settings/billing"
      className={buttonVariants({ variant: "outline", size: "sm" })}
      data-testid={`upgrade-${feature}`}
    >
      <LockIcon />
      {t("Upgrade to unlock")}
    </Link>
  );
}
// #endregion recipe:feature-gate
