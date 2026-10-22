/** The `@bsb-block` line: module, version and mode, read by `sql upgrade`. */
const MODULE_MARKER: RegExp =
  /^-- @(?:bsb-block|bs-module) ([a-z0-9-]+)@(\d+) (managed|adopt)$/m;

/** The installed version of a module file, from its `@bsb-block` line. */
export function moduleFileVersion(
  contents: string,
): { readonly module: string; readonly version: number } | undefined {
  const match = MODULE_MARKER.exec(contents);

  return match ? { module: match[1]!, version: Number(match[2]) } : undefined;
}

/** The `@bsb-block-data` line of a data file. */
const MODULE_DATA_MARKER: RegExp =
  /^-- @(?:bsb-block-data|bs-module-data) ([a-z0-9-]+)$/m;

/** Whether `contents` is a data file `renderBlocks` wrote. */
export const isModuleDataFile = (contents: string): boolean =>
  MODULE_DATA_MARKER.test(contents);

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

const ENTITIES_MARKER = /^-- @(?:bsb-names|bs-entities) ([a-z0-9-]+) (.+)$/gm;

/**
 * The `@bsb-names` line of a module file whose entities are renamed, such as
 * `-- @bsb-names work-items work_item=task/tasks`; undefined without a rename.
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
