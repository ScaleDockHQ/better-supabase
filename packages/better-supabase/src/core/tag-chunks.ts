/**
 * Next.js keeps at most 128 tags from one `cacheTag()` call and drops the rest
 * with a warning. The Postgres cache store reads tags in the same size, which
 * also keeps a PostgREST filter inside the URL limit.
 */
export const MAX_TAGS_PER_CALL = 128;

/** Splits `tags` into lists of at most `size` entries, order kept. */
export function chunkTags(
  tags: Iterable<string>,
  size: number = MAX_TAGS_PER_CALL,
): string[][] {
  const list = [...tags];
  const chunks: string[][] = [];

  for (let from = 0; from < list.length; from += size) {
    chunks.push(list.slice(from, from + size));
  }

  return chunks;
}
