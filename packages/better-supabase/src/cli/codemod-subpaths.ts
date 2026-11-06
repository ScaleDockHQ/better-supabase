/** Renames `better-supabase/<subpath>` import specifiers. */

const SPECIFIER = /(["'])better-supabase\/([\w./-]+)\1/g;

/** `text` with each `better-supabase/<subpath>` specifier in `renames` renamed. */
export function renameSubpaths(
  text: string,
  renames: Readonly<Record<string, string>>,
): string {
  return text.replaceAll(
    SPECIFIER,
    (specifier, quote: string, subpath: string) => {
      const to = Object.hasOwn(renames, subpath) ? renames[subpath] : undefined;

      if (to === undefined) {
        return specifier;
      }

      return to === ""
        ? `${quote}better-supabase${quote}`
        : `${quote}better-supabase/${to}${quote}`;
    },
  );
}
