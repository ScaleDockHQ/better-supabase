import {
  BLOCK_RENAMES,
  currentBlockName,
  formerBlockName,
} from "../../sql/index.ts";

/** Block names match `[a-z0-9-]+`, so quoting needs no escaping. */
const literal = (name: string): string => `'${name}'`;

/** A block installed under its 0.14 name, which `upgrade` moves to the new one. */
export interface RenamedBlock {
  readonly from: string;
  readonly to: string;
}

const MARKER =
  /^(-- @(?:bsb-block|bs-module|bsb-names|bs-entities|bsb-block-data|bs-module-data|bsb-block-test|bs-module-test) )([a-z0-9-]+)(?=[@ \n]|$)/gm;

/** `text` with the 0.14 block names in its markers under their 0.15 names. */
export function withCurrentBlockNames(text: string): string {
  return text.replaceAll(
    MARKER,
    (_line, prefix: string, name: string) =>
      `${prefix}${currentBlockName(name)}`,
  );
}

/** The 0.14 blocks the markers in `text` name, with their 0.15 names. */
export function renamedBlocksIn(text: string): readonly RenamedBlock[] {
  const found = new Set<string>();

  for (const match of text.matchAll(MARKER)) {
    if (Object.hasOwn(BLOCK_RENAMES, match[2]!)) {
      found.add(match[2]!);
    }
  }

  return [...found]
    .toSorted()
    .map((from) => ({ from, to: currentBlockName(from) }));
}

/**
 * Where the 0.14 release wrote `module`'s file at `path`, for a block 0.15
 * renamed; `undefined` for any other block.
 */
export function formerBlockPath(
  path: string,
  module: string,
): string | undefined {
  const from = formerBlockName(module);

  if (from === undefined) {
    return undefined;
  }

  const slug = `_${module.replaceAll("-", "_")}.sql`;

  return path.endsWith(slug)
    ? `${path.slice(0, -slug.length)}_${from.replaceAll("-", "_")}.sql`
    : undefined;
}

/**
 * Moves the `better_supabase.blocks` rows of renamed blocks to their new names.
 * It runs again safely: a row moves only while the new name is free.
 */
export function renamedBlocksSql(renames: readonly RenamedBlock[]): string {
  return `do $bsb_block_names$
begin
  if to_regclass('better_supabase.blocks') is not null then
${renames
  .map(
    ({ from, to }) =>
      `    update better_supabase.blocks set name = ${literal(to)}, updated_at = now()
      where name = ${literal(from)}
        and not exists (select 1 from better_supabase.blocks b where b.name = ${literal(to)});`,
  )
  .join("\n")}
  end if;
end
$bsb_block_names$;`;
}
