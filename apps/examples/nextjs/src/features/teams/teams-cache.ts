import { tagFor } from "better-supabase/next";

/** The tag of one organization's teams, shared by the read and the actions. */
export function teamsTag(organizationId: string): string {
  return tagFor("teams", undefined, { tenant: organizationId });
}
