import type { ListPage } from "better-supabase/blocks";

import { AsyncResult, ok } from "better-supabase";

/** The rows one page reads. */
const PAGE_SIZE = 200;

interface PageRead {
  readonly limit: number;
  readonly after?: readonly string[];
}

/** The most rows one server read collects before the list kit takes over. */
const MAX_ROWS = 500;

/**
 * Reads the keyset pages of a block list one after the other, up to `MAX_ROWS`
 * rows, for a list the list kit still searches and pages on the server
 * (EX-901). A failed page ends the read with its error.
 */
export function readAllPagesResult<Item>(
  read: (page: PageRead) => AsyncResult<ListPage<Item>>,
): AsyncResult<readonly Item[]> {
  return AsyncResult.from(async () => {
    const items: Item[] = [];
    let after: readonly string[] | undefined;

    while (items.length < MAX_ROWS) {
      const options: PageRead = after
        ? { limit: PAGE_SIZE, after }
        : { limit: PAGE_SIZE };

      const page = await read(options);

      if (!page.ok) {
        return page;
      }

      items.push(...page.data.items);

      if (!page.data.hasMore || page.data.nextCursor === null) {
        break;
      }

      after = page.data.nextCursor;
    }

    return ok<readonly Item[]>(items);
  });
}

/** The same read as `readAllPagesResult`, which throws the first error. */
export function readAllPages<Item>(
  read: (page: PageRead) => AsyncResult<ListPage<Item>>,
): Promise<readonly Item[]> {
  return readAllPagesResult(read).orThrow();
}
