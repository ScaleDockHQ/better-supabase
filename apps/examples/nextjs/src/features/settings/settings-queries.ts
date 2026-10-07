import "server-only";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/** The caller's own settings, with the defaults from `settings-definition.ts`. */
export async function getUserSettings() {
  "use cache: private";
  const { supabase } = await bs.cached();
  return blocks(supabase).settings.user.get().orThrow();
}

/** Takes the organization as an argument: the private cache keys on it. */
export async function getOrganizationSettings(organizationId: string) {
  "use cache: private";
  const { supabase } = await bs.cached();
  return blocks(supabase).settings.organization.get(organizationId).orThrow();
}
