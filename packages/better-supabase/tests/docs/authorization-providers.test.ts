import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { TEMPLATE_PLACEHOLDERS } from "../../src/core/access-sql.ts";

const page = readFileSync(
  new URL(
    "../../../../apps/docs/content/docs/(reference)/extending/authorization-providers.mdx",
    import.meta.url,
  ),
  "utf-8",
);

describe("authorization provider docs", () => {
  it("lists every function template in the placeholder table", () => {
    const start = page.indexOf("| Template");
    const end = page.indexOf("`rowsWith` answers");
    const table = page.slice(start, end);

    const names = [...table.matchAll(/^\| `(\w+)`/gm)].flatMap((match) =>
      match[1] === undefined ? [] : [match[1]],
    );

    const compare = (left: string, right: string): number =>
      left.localeCompare(right);

    expect(names.toSorted(compare)).toEqual(
      Object.keys(TEMPLATE_PLACEHOLDERS).toSorted(compare),
    );
  });
});
