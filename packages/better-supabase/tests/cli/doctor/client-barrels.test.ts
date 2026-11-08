import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { CLIENT_BARREL_RULES } from "../../../src/cli/doctor/client-barrels.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";

const config = resolveConfig(
  { gen: { file: "src/lib/supabase/generated.ts" } },
  "/app",
);

function check(
  sources: { path: string; text: string }[],
  override = config,
): readonly { message: string; location?: { line: number } }[] {
  const [rule] = CLIENT_BARREL_RULES;

  // SAFETY: BS621 reads only `config` and `sources`.
  const findings = rule?.check({
    config: override,
    sources,
  } as unknown as DoctorContext);

  if (!Array.isArray(findings)) {
    throw new TypeError("BS621 runs synchronously");
  }

  return findings;
}

describe("BS621", () => {
  it("flags a client file that imports the schema or block barrels", () => {
    const findings = check([
      {
        path: "src/app/list.tsx",
        text: [
          '"use client";',
          "",
          'import { schema } from "../lib/supabase/generated-schema";',
          'import { blockConfig } from "@/lib/supabase/blocks.config";',
        ].join("\n"),
      },
    ]);

    expect(findings).toHaveLength(2);
    expect(findings[0]?.location?.line).toBe(3);
    expect(findings[0]?.message).toContain("every table");
    expect(findings[1]?.message).toContain("every block");
  });

  it("leaves server files, table modules and slices alone", () => {
    expect(
      check([
        {
          path: "src/app/page.tsx",
          text: 'import { schema } from "../lib/supabase/generated-schema";',
        },
        {
          path: "src/app/list.tsx",
          text: '"use client";\nimport { customersTable } from "../lib/supabase/tables/customers";\nimport { tagsConfig } from "../lib/supabase/blocks/slices";',
        },
      ]),
    ).toEqual([]);
  });

  it("is off with the single-module layout", () => {
    expect(
      check(
        [
          {
            path: "src/app/list.tsx",
            text: '"use client";\nimport { schema } from "../lib/supabase/generated-schema";',
          },
        ],
        resolveConfig(
          {
            gen: { file: "src/lib/supabase/generated.ts", tableModules: false },
          },
          "/app",
        ),
      ),
    ).toEqual([]);
  });
});
