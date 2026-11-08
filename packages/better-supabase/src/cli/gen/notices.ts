import type { ResolvedConfig } from "../../config/index.ts";
import type { Snapshot } from "../introspect/types.ts";

import { METADATA_GAPS_TEXT } from "../introspect/from-metadata.ts";
import {
  oxfmtInstalled,
  typegenVersion,
  typegenVersionNotice,
} from "../introspect/typegen.ts";
import { declaredPeers, installedVersion, satisfies } from "../peers.ts";

export const UNFORMATTED =
  'oxfmt is not installed, so database.types.ts is not formatted like `supabase gen types` output. Install it: pnpm add -D oxfmt. @supabase/postgrest-typegen pins oxfmt 0.66.0 as its peer; to allow a newer one, add it to peerDependencyRules.allowedVersions in pnpm-workspace.yaml, keyed "@supabase/postgrest-typegen>oxfmt".';

const METADATA_ONLY = `Notice: the schema came from a GeneratorMetadata document, which has no ${METADATA_GAPS_TEXT}. Unique keys and checks cover single columns, relations have no onDelete, and a column a CHECK makes not null stays required on insert even when a before-insert trigger assigns it. Run \`better-supabase gen\` against the database for the full model.`;

/**
 * The library each first-party generator writes imports of, by the generator's
 * name. Its range is the peer range better-supabase declares and tests.
 */
const GENERATED_LIBRARIES: Readonly<Record<string, string>> = {
  zod: "zod",
  valibot: "valibot",
  nuqs: "nuqs",
};

/**
 * One notice for each configured generator whose library is installed in a
 * version outside the tested range. A library that isn't installed gets none:
 * the app's own type check says so.
 */
export async function generatedLibraryNotices(
  config: ResolvedConfig,
): Promise<string[]> {
  const peers = await declaredPeers();

  const found = await Promise.all(
    config.generators.flatMap((generator) => {
      const library = GENERATED_LIBRARIES[generator.name];
      const range = library === undefined ? undefined : peers[library];

      return library === undefined || range === undefined
        ? []
        : [
            installedVersion(library, config.root).then(
              (installed): string[] =>
                installed !== undefined && satisfies(installed, range) === false
                  ? [
                      `Notice: the ${generator.name}() generator writes code for ${library} ${range}, and ${library} ${installed} is installed. The generated files may not type-check or run; install a version in range.`,
                    ]
                  : [],
            ),
          ];
    }),
  );

  return found.flat();
}

/**
 * The formatter, typegen version and metadata-only notices, the model's notices
 * and the config warnings, one line each. With the `config`, a generator whose
 * library is outside its tested range adds a notice.
 */
export async function generationNotices(
  snapshot: Snapshot,
  warnings: readonly string[],
  notices: readonly string[] = [],
  config?: ResolvedConfig,
): Promise<string[]> {
  const typegen = typegenVersionNotice(await typegenVersion());
  const generated = config ? await generatedLibraryNotices(config) : [];

  return [
    ...((await oxfmtInstalled()) ? [] : [UNFORMATTED]),
    ...(typegen ? [typegen] : []),
    ...(snapshot.extras.fromMetadata ? [METADATA_ONLY] : []),
    ...generated,
    ...notices,
    ...warnings.map((warning) => `Warning: ${warning}`),
  ];
}
