/** The `@bs-module` line: module, version and mode, read by `sql upgrade`. */
const MODULE_MARKER: RegExp =
  /^-- @bs-module ([a-z0-9-]+)@(\d+) (managed|adopt)$/m;

/** The installed version of a module file, from its `@bs-module` line. */
export function moduleFileVersion(
  contents: string,
): { readonly module: string; readonly version: number } | undefined {
  const match = MODULE_MARKER.exec(contents);

  return match ? { module: match[1]!, version: Number(match[2]) } : undefined;
}

/** The `@bs-module-data` line of a data file. */
const MODULE_DATA_MARKER: RegExp = /^-- @bs-module-data ([a-z0-9-]+)$/m;

/** Whether `contents` is a data file `renderModules` wrote. */
export const isModuleDataFile = (contents: string): boolean =>
  MODULE_DATA_MARKER.test(contents);

/** Whether an installed file matches, ignoring line endings and the version releases before 0.13 stamped in its header. */
export function sameModuleFile(
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
