import { describe, expect, it } from "vitest";

import {
  removeAdoptOwnership,
  withoutAdoptOwnership,
} from "../../../src/cli/sql/config-adopt.ts";

describe("removeAdoptOwnership", () => {
  it("removes the key and keeps the tables and columns mappings", () => {
    const source = `export default defineConfig({
  blocks: {
    // the app's own audit log
    audit: {
      ownership: "adopt",
      tables: { log: "public.audit_log" },
      columns: { log: { actor: "user_id" } },
    },
    tags: { ownership: 'adopt', tables: { tags: "public.labels" } },
    teams: { ownership: "custom" },
  },
});
`;

    const { text, review } = removeAdoptOwnership(source, false);

    expect(text).toBe(`export default defineConfig({
  blocks: {
    // the app's own audit log
    audit: {
      tables: { log: "public.audit_log" },
      columns: { log: { actor: "user_id" } },
    },
    tags: { tables: { tags: "public.labels" } },
    teams: { ownership: "custom" },
  },
});
`);
    expect(review.map((line) => line.line)).toEqual([5, 8]);
  });

  it("drops the comma before a last property", () => {
    const source = `{
  "blocks": {
    "audit": {
      "tables": { "log": "public.audit_log" },
      "ownership": "adopt"
    },
    "tags": { "tables": { "tags": "public.labels" }, "ownership": "adopt" }
  }
}
`;

    const { text } = removeAdoptOwnership(source, true);

    expect(JSON.parse(text)).toEqual({
      blocks: {
        audit: { tables: { log: "public.audit_log" } },
        tags: { tables: { tags: "public.labels" } },
      },
    });
  });

  it("leaves strings and comments alone", () => {
    const source = `export default defineConfig({
  // ownership: "adopt" was the old way
  docs: 'ownership: "adopt"',
  blocks: { audit: {} },
});
`;

    expect(removeAdoptOwnership(source, false)).toEqual({
      text: source,
      review: [],
    });
  });

  it("passes a refused edit through", () => {
    const refused = { ok: false as const, reason: "it isn't valid JSON" };

    expect(withoutAdoptOwnership(refused, true)).toBe(refused);
  });
});
