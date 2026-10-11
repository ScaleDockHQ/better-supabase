import type { Snapshot } from "../introspect/types.ts";

import { METADATA_GAPS_TEXT } from "../introspect/from-metadata.ts";
import {
  oxfmtInstalled,
  typegenVersion,
  typegenVersionNotice,
} from "../introspect/typegen.ts";

export const UNFORMATTED =
  'oxfmt is not installed, so database.types.ts is not formatted like `supabase gen types` output. Install it: pnpm add -D oxfmt. @supabase/postgrest-typegen pins oxfmt 0.66.0 as its peer; to allow a newer one, add it to peerDependencyRules.allowedVersions in pnpm-workspace.yaml, keyed "@supabase/postgrest-typegen>oxfmt".';

const METADATA_ONLY = `Notice: the schema came from a GeneratorMetadata document, which has no ${METADATA_GAPS_TEXT}. Unique keys and checks cover single columns, relations have no onDelete, and columns a before-insert trigger fills stay required on insert. Run \`better-supabase gen\` against the database for the full model.`;

/** The formatter, typegen version and metadata-only notices and the config warnings, one line each. */
export async function generationNotices(
  snapshot: Snapshot,
  warnings: readonly string[],
): Promise<string[]> {
  const typegen = typegenVersionNotice(await typegenVersion());
  return [
    ...((await oxfmtInstalled()) ? [] : [UNFORMATTED]),
    ...(typegen ? [typegen] : []),
    ...(snapshot.extras.fromMetadata ? [METADATA_ONLY] : []),
    ...warnings.map((warning) => `Warning: ${warning}`),
  ];
}
