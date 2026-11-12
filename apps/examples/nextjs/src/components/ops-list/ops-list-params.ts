import type { inferParserType } from "nuqs/server";

import { createLoader, parseAsString } from "nuqs/server";

/**
 * The URL state of a list that reads a block's API (`ai_runs`, prompts, eval
 * runs) instead of a list query: a search, one named filter, a sort and a
 * keyset cursor. The page parses it with `loadOpsList` and the toolbar writes
 * it with `shallow: false`, so the server renders each state and no list
 * filters or sorts in the browser.
 */
export const opsListParams = {
  q: parseAsString.withDefault(""),
  filter: parseAsString,
  sort: parseAsString,
  cursor: parseAsString,
};

export const loadOpsList = createLoader(opsListParams);

export type OpsListQuery = inferParserType<typeof opsListParams>;
