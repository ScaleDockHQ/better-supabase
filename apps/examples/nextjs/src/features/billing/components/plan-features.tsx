import { hasEntitlement } from "better-supabase/next";

import { getSession } from "@/features/user/user-queries";
import { type Entitlement } from "@/lib/claims";

const FEATURES: Record<Entitlement, string> = {
  exports: "CSV exports",
  sso: "Single sign-on",
  audit: "Audit log",
};

/**
 * The plan's features from the token's `features` claim. UX only:
 * `better_supabase.has_entitlement()` enforces them in RLS.
 */
export async function PlanFeatures() {
  const session = await getSession();
  const orgId =
    session.kind === "user"
      ? (session.claims.tenant_id ?? session.claims.app_metadata?.tenant_id)
      : undefined;
  if (!orgId) return null;
  // SAFETY: FEATURES is keyed by Entitlement, and Object.entries widens the
  // keys to string.
  return (
    <ul aria-label="Plan features">
      {Object.entries(FEATURES).map(([key, label]) => (
        <li key={key}>
          {label}:{" "}
          {hasEntitlement(session, orgId, key as Entitlement)
            ? "included"
            : "not in your plan"}
        </li>
      ))}
    </ul>
  );
}
