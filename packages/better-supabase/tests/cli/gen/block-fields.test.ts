import { describe, expect, it } from "vitest";

import { generatedOptions } from "../../../src/blocks/block-config.ts";
import { blockConfigEntries } from "../../../src/cli/gen/blocks.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { appColumnsOf } from "../../../src/sql/index.ts";

const TABLES = {
  expenses: "expense_reports",
  leave: "leave_requests",
  catalog: "products",
  tasks: "tasks",
  "time-entries": "time_entries",
  teams: "teams",
  flags: "flags",
} as const;

const files = Object.values(TABLES).map((table) => ({
  path: `supabase/schemas/${table}.sql`,
  text: `alter table better_supabase.${table} add column cost_code text not null default 'none';
alter table better_supabase.${table} add column ledger_ref text not null;
alter table better_supabase.${table} add column hint_text text;
`,
}));

const config = resolveConfig(
  // SAFETY: the test passes only block keys the config accepts.
  { blocks: Object.fromEntries(Object.keys(TABLES).map((name) => [name, {}])) },
  "/tmp/block-fields",
);

const entries = blockConfigEntries(config, undefined, appColumnsOf(files));

describe.each(Object.keys(TABLES))("block slice fields of %s", (name) => {
  const entry = entries[name]!;

  const { fields } = generatedOptions(entry) as unknown as {
    fields: { "~standard": { validate: (value: unknown) => unknown } };
  };

  it("carries the columns the app's files add, with their types", () => {
    expect(entry.columns).toEqual({
      cost_code: "text not null default 'none'",
      ledger_ref: "text not null",
      hint_text: "text",
    });
  });

  it("lets a not null column with a default be missing on insert", () => {
    expect(fields["~standard"].validate({ ledger_ref: "a" })).toMatchObject({
      value: { ledger_ref: "a" },
    });
  });

  it("still requires a not null column without a default", () => {
    expect(fields["~standard"].validate({ cost_code: "x" })).toHaveProperty(
      "issues",
    );
  });
});

describe("block slices without app columns", () => {
  it("pass no fields", () => {
    const bare = blockConfigEntries(config, undefined, appColumnsOf([]));

    for (const name of Object.keys(TABLES)) {
      expect(bare[name]?.columns).toBeUndefined();
      expect(generatedOptions(bare[name]!)).not.toHaveProperty("fields");
    }
  });
});
