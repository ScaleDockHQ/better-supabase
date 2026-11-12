import { bsbCore } from "@/lib/supabase/server-core";

import { AuthzRefresh } from "./authz-refresh";

/**
 * Starts the session read for `AuthzRefresh` inside its own boundary, so the
 * shell never waits for it. Mounted by the signed-in layout: a token that was
 * issued before a permission change (a migration, a role edit) catches up to
 * the live authorization version on the next page load (EX-906).
 */
export function SessionAuthzRefresh() {
  return <AuthzRefresh session={bsbCore.claims()} />;
}
