import { parseAsString } from "nuqs/server";

/**
 * The URL state of a block overview, shared by the server (`parseBlockList`)
 * and the client grid (`BlockListView`), so both read the same keys with the
 * same defaults. `f` is the one facet filter and `after` the keyset cursor.
 */
export const blockOverviewParsers = {
  q: parseAsString.withDefault(""),
  f: parseAsString.withDefault(""),
  sort: parseAsString.withDefault(""),
  after: parseAsString.withDefault(""),
};
