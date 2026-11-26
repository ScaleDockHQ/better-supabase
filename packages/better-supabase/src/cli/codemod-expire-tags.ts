import type { ReviewLine } from "./codemod.ts";

import { lineColumn } from "./config-document/parse.ts";
import { nextCacheCalls } from "./doctor/kept-expiry.ts";

/**
 * Lists each `updateTag` and `revalidateTag` call and the `bsb.expireTags` call
 * that replaces it. The call becomes `await`, so the enclosing function must be
 * async and `bsb` imported there; the codemod names the line and leaves the
 * text.
 */
export function reportExpireTags(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const review = nextCacheCalls(text)
    .filter((call) => call.name !== "refresh")
    .map((call) => {
      const tags = call.argument === undefined ? "[]" : `[${call.argument}]`;

      return {
        line: lineColumn(text, call.start).line,
        message: `${call.name}() expires Next's cache only. Replace it with \`await bsb.expireTags(${tags})\`, which also expires the kept store.`,
      };
    });

  return { text, review };
}
