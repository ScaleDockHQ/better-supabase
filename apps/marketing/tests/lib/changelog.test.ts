import { describe, expect, test } from "vitest";

import { parseChangelog } from "../../lib/changelog";

const sample = `# better-supabase

## 0.2.0

### Minor Changes

- 258e0aa: Add the storage block.
- Thread casing through includes,
  including nested filters.

### Patch Changes

- 8f79c80: Fix doctor help links.

## 0.1.0

### Minor Changes

- abcdef0: First release.
`;

describe("parseChangelog", () => {
  test("groups versions, kinds and hashed bullets", () => {
    const releases = parseChangelog(sample);
    expect(releases).toHaveLength(3);
    expect(releases[0]).toMatchObject({ version: "0.2.0", kind: "Minor" });
    expect(releases[0]?.changes[0]).toEqual({
      hash: "258e0aa",
      text: "Add the storage block.",
    });
    expect(releases[1]?.kind).toBe("Patch");
    expect(releases[2]?.version).toBe("0.1.0");
  });

  test("joins wrapped bullet lines", () => {
    const releases = parseChangelog(sample);
    expect(releases[0]?.changes[1]).toEqual({
      text: "Thread casing through includes, including nested filters.",
    });
  });

  test("returns nothing for an empty changelog", () => {
    expect(parseChangelog("# better-supabase\n")).toEqual([]);
  });
});
