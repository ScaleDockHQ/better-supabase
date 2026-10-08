import { hasEntitlement } from "better-supabase/blocks/entitlements";
import { CheckIcon, MinusIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { Entitlement } from "@/lib/claims";

import { activeOrganizationId } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

/**
 * The plan's features from the token's `features` claim. UX only:
 * `better_supabase.has_entitlement()` enforces them in RLS.
 */
export async function PlanFeatures() {
  const [session, t] = await Promise.all([
    getSession(),
    getExtracted("billing"),
  ]);
  const organizationId = activeOrganizationId(session);
  if (!organizationId) return null;
  const features = [
    ["exports", t("CSV exports")],
    ["audit", t("Audit log")],
    ["sso", t("Single sign-on")],
  ] satisfies readonly (readonly [Entitlement, string])[];
  return (
    <ul aria-label={t("Plan features")} className="space-y-2 text-sm">
      {features.map(([key, label]) => {
        const included = hasEntitlement(session, organizationId, key);
        return (
          <li key={key} className="flex items-center gap-2">
            {included ? (
              <CheckIcon className="text-primary size-4" />
            ) : (
              <MinusIcon className="text-muted-foreground size-4" />
            )}
            <span className={included ? undefined : "text-muted-foreground"}>
              {label}
            </span>
            <span className="sr-only">
              {included ? t("included") : t("not in your plan")}
            </span>
          </li>
        );
      })}
    </ul>
  );
}
