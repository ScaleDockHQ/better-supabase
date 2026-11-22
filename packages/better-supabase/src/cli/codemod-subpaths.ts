/** Renames `better-supabase/<subpath>` import specifiers. */

import { MagicString } from "magic-string";
import { parseSync } from "oxc-parser";
import { walk } from "oxc-walker";

/**
 * `text` with each `better-supabase/<subpath>` module specifier in `renames`
 * renamed. A specifier is a string literal that holds exactly the module name
 * (an import, an export, `import()`, `require()` or `vi.mock()`), so a comment
 * or a longer string that mentions one stays as it is.
 */
export function renameSubpaths(
  text: string,
  renames: Readonly<Record<string, string>>,
): string {
  const parsed = parseSync("source.tsx", text, { sourceType: "module" });
  const out = new MagicString(text);

  walk(parsed.program, {
    enter(node) {
      if (node.type !== "Literal" || typeof node.value !== "string") {
        return;
      }

      const prefix = "better-supabase/";

      if (!node.value.startsWith(prefix)) {
        return;
      }

      const subpath = node.value.slice(prefix.length);
      const to = Object.hasOwn(renames, subpath) ? renames[subpath] : undefined;

      if (to === undefined) {
        return;
      }

      const quote = text[node.start]!;

      out.overwrite(
        node.start,
        node.end,
        to === ""
          ? `${quote}better-supabase${quote}`
          : `${quote}${prefix}${to}${quote}`,
      );
    },
  });

  return out.toString();
}
