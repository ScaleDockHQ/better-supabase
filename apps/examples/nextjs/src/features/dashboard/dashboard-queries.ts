import "server-only";
import { workspaceSummary } from "@/lib/read-sets";
import { bs } from "@/lib/supabase/server";

/**
 * Four numbers, one GET: the read set runs as a single `stable` function.
 * `cacheTags` tags the entry with every table the set reads, so a new
 * customer or note revalidates it.
 */
export async function getWorkspaceSummary() {
  "use cache: private";
  const { db, session } = await bs.cached();
  bs.cacheTags(workspaceSummary);
  if (session.kind !== "user") return null;
  return db.$many(workspaceSummary, { userId: session.user.id }).orThrow();
}
