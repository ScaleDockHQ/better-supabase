import { describe, expect, it } from "vitest";

import type { DoctorContext, TextFile } from "../../../src/cli/doctor/rules.ts";

import { REMOVED_API_RULES } from "../../../src/cli/doctor/removed-apis.ts";

function check(sources: TextFile[]): readonly string[] {
  const [rule] = REMOVED_API_RULES;
  // SAFETY: BS418 reads only `sources`.
  const context = { sources } as unknown as DoctorContext;
  const findings = rule?.check(context);

  if (!Array.isArray(findings)) {
    throw new TypeError("BS418 runs synchronously");
  }

  return findings.map((finding: { message: string }) => finding.message);
}

describe("BS418", () => {
  it("names the 0.15 subpath of a renamed block", () => {
    expect(
      check([
        {
          path: "src/app.ts",
          text: 'import { workItemsBlock } from "better-supabase/blocks/work-items";',
        },
      ]),
    ).toEqual([
      expect.stringContaining("renamed to `better-supabase/blocks/tasks`"),
      expect.stringContaining("renamed to `tasksBlock`"),
    ]);
  });

  it("names the block that replaced a plugin subpath", () => {
    expect(
      check([
        {
          path: "src/db.ts",
          text: 'import { softDelete } from "better-supabase/plugins/soft-delete";',
        },
      ]),
    ).toEqual([
      expect.stringContaining("renamed to `better-supabase/blocks/trash`"),
    ]);
  });

  it("points removed record feature APIs at record types", () => {
    expect(
      check([
        {
          path: "src/actions.ts",
          text: "export const run = bsb.sectionAction(feature);",
        },
      ]),
    ).toEqual([expect.stringContaining("bsb.record(<type>Record)")]);
  });

  it("passes code on the 0.15 names", () => {
    expect(
      check([
        {
          path: "src/app.ts",
          text: 'import { tasksBlock } from "better-supabase/blocks/tasks";',
        },
      ]),
    ).toEqual([]);
  });
});
