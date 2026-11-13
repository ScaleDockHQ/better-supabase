import type { BlockSqlEntitySpec } from "../sql/context.ts";
import type { BlockEntities } from "./entity-surface.ts";

/**
 * The entity spec with the search registration its manifest entity implies (ADR
 * 0831). A subject whose SQL module names no `search` gets its title column and
 * the body columns the manifest's `search` lists; `search: false` on the
 * manifest entity keeps it out. A module's own `search` always wins.
 */
export function withSearchDefault(
  spec: BlockSqlEntitySpec,
  entities: BlockEntities,
): BlockSqlEntitySpec {
  const subject = spec.subject;

  if (subject === undefined || subject.search !== undefined) {
    return spec;
  }

  const declared = entities[spec.singular]?.search;

  if (declared === false) {
    return spec;
  }

  return {
    ...spec,
    subject: {
      ...subject,
      search: {
        title: subject.title,
        body: Array.isArray(declared) ? declared : [],
      },
    },
  };
}
