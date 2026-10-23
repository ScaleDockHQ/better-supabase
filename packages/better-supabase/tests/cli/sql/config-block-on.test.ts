import { describe, expect, it } from "vitest";

import {
  moveSubjectsToOnInSource,
  withSubjectsOn,
} from "../../../src/cli/sql/config-block-on.ts";

describe("moveSubjectsToOnInSource", () => {
  it("moves options.subjects to on and drops an emptied options", () => {
    const source = `export default defineConfig({
  blocks: {
    // tags on deals
    tags: { options: { subjects: ["deal"] } },
    comments: {},
  },
});
`;

    expect(moveSubjectsToOnInSource(source)).toEqual({
      text: `export default defineConfig({
  blocks: {
    // tags on deals
    tags: { on: ["deal"] },
    comments: {},
  },
});
`,
      review: [],
    });
  });

  it("keeps the other options", () => {
    const source = `export default defineConfig({
  blocks: {
    attachments: {
      options: {
        subjects: {
          deal: { kinds: ["contract"] },
        },
        maxBytes: 10,
      },
    },
  },
});
`;

    expect(moveSubjectsToOnInSource(source).text)
      .toBe(`export default defineConfig({
  blocks: {
    attachments: {
      on: {
        deal: { kinds: ["contract"] },
      },
      options: {
        maxBytes: 10,
      },
    },
  },
});
`);
  });

  it("wraps field history's column lists in fields", () => {
    const source = `defineConfig({
  blocks: { "field-history": { options: { subjects: { deal: ["amount"] } } } },
});
`;

    expect(moveSubjectsToOnInSource(source).text).toBe(`defineConfig({
  blocks: { "field-history": { on: { deal: { fields: ["amount"] } } } },
});
`);
  });

  it("moves a shorthand property", () => {
    expect(
      moveSubjectsToOnInSource(
        "defineConfig({ blocks: { tags: { options: { subjects } } } });",
      ).text,
    ).toBe("defineConfig({ blocks: { tags: { on: subjects } } });");
  });

  it("lists an entry that already sets on for review", () => {
    const moved = moveSubjectsToOnInSource(
      `defineConfig({
  blocks: { tags: { on: ["deal"], options: { subjects: ["task"] } } },
});`,
    );

    expect(moved.review).toEqual([expect.objectContaining({ line: 2 })]);
    expect(moved.text).toContain('options: { subjects: ["task"] }');
  });
});

describe("withSubjectsOn", () => {
  it("moves subjects in a JSON config", () => {
    const edit = withSubjectsOn(
      {
        ok: true,
        text: JSON.stringify({
          blocks: {
            tags: { options: { subjects: ["deal"], limit: 3 } },
            "field-history": { options: { subjects: { deal: ["amount"] } } },
          },
        }),
      },
      true,
    );

    expect(edit.ok && JSON.parse(edit.text)).toEqual({
      blocks: {
        tags: { on: ["deal"], options: { limit: 3 } },
        "field-history": { on: { deal: { fields: ["amount"] } } },
      },
    });
  });

  it("passes a refusal through", () => {
    expect(withSubjectsOn({ ok: false, reason: "no" }, false)).toEqual({
      ok: false,
      reason: "no",
    });
  });
});
