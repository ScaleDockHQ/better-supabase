import type { Snapshot } from "../introspect/types.ts";
import type { Finding, Rule } from "./rules.ts";

import { METADATA_GAPS_TEXT } from "../introspect/from-metadata.ts";

/**
 * Rules that read what a `GeneratorMetadata` document leaves out (policies,
 * grants, indexes, triggers, buckets, the realtime publication, foreign key
 * actions, multi-column constraints, role settings, hook functions). On a
 * snapshot built from such a document they would report what is missing
 * from the document, not from the database, so they skip with an info finding.
 */
export const EXTRAS_RULES: ReadonlySet<string> = new Set([
  "BS103",
  "BS106",
  "BS107",
  "BS108",
  "BS109",
  "BS110",
  "BS111",
  "BS112",
  "BS113",
  "BS114",
  "BS204",
  "BS205",
  "BS206",
  "BS207",
  "BS210",
  "BS211",
  "BS213",
  "BS215",
  "BS216",
  "BS217",
  "BS218",
  "BS219",
  "BS301",
  "BS302",
  "BS303",
  "BS305",
  "BS306",
  "BS310",
  "BS315",
  "BS404",
  "BS405",
  "BS406",
  "BS407",
]);

/** The info finding for a rule in `EXTRAS_RULES` that did not run, or `undefined` when it can. */
export function skippedForMetadata(
  snapshot: Snapshot,
  rule: Pick<Rule, "code" | "title">,
  help: string,
): Finding | undefined {
  if (!snapshot.extras.fromMetadata || !EXTRAS_RULES.has(rule.code))
    return undefined;
  return {
    code: rule.code,
    severity: "info",
    title: rule.title,
    help,
    message: `Skipped: the schema came from a GeneratorMetadata document (--metadata), which has no ${METADATA_GAPS_TEXT}. Run doctor against the database to run this check.`,
  };
}
