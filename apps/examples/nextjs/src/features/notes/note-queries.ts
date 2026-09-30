import "server-only";
import { next } from "@/lib/supabase.server";

/**
 * The latest embedded note and the notes nearest to it. `db.$search` calls
 * `search_notes` (the vector-search SQL kit module), a security invoker
 * function, so RLS keeps other organizations' notes out and the HNSW scan
 * keeps going until it has `k` visible rows. A real app would embed a search
 * box's text with a model and pass that vector instead.
 */
export async function getSimilarNotes() {
  "use cache: private";
  const { db } = await next.cached();
  const source = await db.notes
    .findFirst({
      select: ["id", "body", "embedding"],
      where: { embedding: { isNull: false } },
      orderBy: { id: "desc" },
    })
    .orThrow();
  if (!source?.embedding) return null;
  const similar = await db
    .$search("notes", {
      vector: source.embedding,
      k: 3,
      select: ["id", "body", "kind"],
      where: { id: { neq: source.id } },
    })
    .orThrow();
  return { source, similar };
}
