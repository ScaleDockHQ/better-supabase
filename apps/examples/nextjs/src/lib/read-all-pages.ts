import type { AsyncResult } from "better-supabase";
import type { ListPage } from "better-supabase/blocks";

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
 * (EX-901).
 */
export async function readAllPages<Item>(
  read: (page: PageRead) => AsyncResult<ListPage<Item>>,
): Promise<readonly Item[]> {
  const items: Item[] = [];
  let after: readonly string[] | undefined;

  while (items.length < MAX_ROWS) {
    const options: PageRead = after
      ? { limit: PAGE_SIZE, after }
      : { limit: PAGE_SIZE };

    const page = await read(options).orThrow();
    items.push(...page.items);

    if (!page.hasMore || page.nextCursor === null) {
      break;
    }

    after = page.nextCursor;
  }

  return items;
}
