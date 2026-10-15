import type { SearchHit } from "./search.ts";

/** A row of the dialog: a match, a recent or a favorite. */
export interface CommandSearchItem {
  readonly subjectType: string;
  readonly subjectId: string;
  readonly title: string | null;
  readonly url: string | null;
  readonly snippet?: string | null;
}

/** One heading of the dialog: `favorites`, `recents`, or a subject type. */
export interface CommandSearchGroup {
  readonly key: string;
  readonly items: readonly CommandSearchItem[];
}

/** Groups matches by subject type, in the order the best match of each appears. */
export function groupHits(
  hits: readonly SearchHit[],
): readonly CommandSearchGroup[] {
  const groups = new Map<string, CommandSearchItem[]>();
  for (const hit of hits) {
    const items = groups.get(hit.subjectType);
    if (items === undefined) groups.set(hit.subjectType, [hit]);
    else items.push(hit);
  }
  return [...groups].map(([key, items]) => ({ key, items }));
}
