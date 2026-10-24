import { sha256Hex } from "./sha256.ts";

/**
 * The `@bsb-block` line: instance, version, mode and, for an instance that
 * installs a block under another name, the block. `upgrade` reads it.
 */
const MODULE_MARKER: RegExp =
  /^-- @(?:bsb-block|bs-module) ([a-zA-Z0-9-]+)@(\d+) (managed|adopt)(?: ([a-z0-9-]+))?$/m;

/**
 * The installed version of a module file, from its `@bsb-block` line: `module`
 * is the instance, and `block` the block an instance with another name
 * installs.
 */
export function moduleFileVersion(
  contents: string,
):
  | {
      readonly module: string;
      readonly block?: string;
      readonly version: number;
    }
  | undefined {
  const match = MODULE_MARKER.exec(contents);

  return match
    ? {
        module: match[1]!,
        ...(match[4] === undefined ? {} : { block: match[4] }),
        version: Number(match[2]),
      }
    : undefined;
}

/** The `@bsb-block-data` line of a data file. */
const MODULE_DATA_MARKER: RegExp =
  /^-- @(?:bsb-block-data|bs-module-data) ([a-zA-Z0-9-]+)$/m;

/** Whether `contents` is a data file `renderBlocks` wrote. */
export const isModuleDataFile = (contents: string): boolean =>
  MODULE_DATA_MARKER.test(contents);

const HASH_LINE = /^-- @bsb-hash sha256:([0-9a-f]{64})$/m;

/** The SQL after the header. The hash covers this and not the header. */
function blockBody(contents: string): string {
  const split = contents.indexOf("\n\n");

  return split === -1 ? "" : contents.slice(split + 2);
}

/**
 * `contents` with a `-- @bsb-hash` line after its block marker. The hash is
 * SHA-256 of the body, so a later edit of the SQL no longer matches.
 */
export function withBlockHash(contents: string): string {
  if (HASH_LINE.test(contents)) {
    return contents;
  }

  const line = `-- @bsb-hash sha256:${sha256Hex(blockBody(contents))}`;

  const marker = /^(-- @bsb-(?:block|block-data|block-test|tables)[^\n]*)\n/m;

  return marker.test(contents)
    ? contents.replace(marker, `$1\n${line}\n`)
    : `${line}\n${contents}`;
}

/**
 * Whether the hash line matches the body. `missing` is a file from before
 * hashes, which sync may still rewrite. `edited` is a body someone changed
 * without updating the hash.
 */
export function blockFileState(
  contents: string,
): "clean" | "missing" | "edited" {
  const match = HASH_LINE.exec(contents);

  if (match === null) {
    return "missing";
  }

  return match[1] === sha256Hex(blockBody(contents)) ? "clean" : "edited";
}

/**
 * Whether an installed file matches, ignoring line endings and the version
 * releases before 0.13 stamped in its header.
 */
export function sameBlockFile(
  current: string | undefined,
  expected: string,
): boolean {
  if (current === undefined) {
    return false;
  }

  const strip = (text: string): string =>
    text
      .replaceAll("\r\n", "\n")
      .replace(
        /^(-- better-supabase module: [^\n(]*?)(?: \([^)]*\))?\n/,
        "$1\n",
      );

  return strip(current) === strip(expected);
}

const ENTITIES_MARKER =
  /^-- @(?:bsb-names|bs-entities) ([a-zA-Z0-9-]+) (.+)$/gm;

/**
 * The `@bsb-names` line of a module file whose entities are renamed, such as
 * `-- @bsb-names tasks work_item=task/tasks`; undefined without a rename.
 */
export function entitiesMarker(
  module: string,
  renames: readonly {
    readonly key: string;
    readonly singular: string;
    readonly plural: string;
  }[],
): string | undefined {
  return renames.length === 0
    ? undefined
    : `-- @bsb-names ${module} ${renames
        .map((rename) => `${rename.key}=${rename.singular}/${rename.plural}`)
        .join(" ")}`;
}

/** Module to its entity renames, from the `@bsb-names` lines in `text`. */
export function entityMarkers(text: string): ReadonlyMap<string, string> {
  return new Map(
    [...text.matchAll(ENTITIES_MARKER)].map((match) => [
      match[1] ?? "",
      match[2] ?? "",
    ]),
  );
}
