import { bsb } from "@/lib/supabase/server";

import { liveAuthzVersion } from "../live-version";
import { AuthzRefresh } from "./authz-refresh";

/**
 * Starts the session read for `AuthzRefresh` inside its own boundary, so the
 * shell never waits for it. Mounted by the signed-in layout: a token that was
 * issued before a permission change (a migration, a role edit) catches up to
 * the live authorization version on the next page load (EX-906). The server
 * reads that version once and the client reports it on the first join, so the
 * browser does not call `caller_authz_version()` itself.
 */
export async function SessionAuthzRefresh() {
  const session = bsb.claims();
  const liveVersion = await liveAuthzVersion();

  return <AuthzRefresh session={session} liveVersion={liveVersion} />;
}
