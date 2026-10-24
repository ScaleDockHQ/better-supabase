import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { NOT_VALID_RULES } from "../../../src/cli/doctor/not-valid.ts";
import { RULE_CODES } from "../../../src/cli/doctor/rules.ts";

const CHECKS = [
  {
    schema: "public",
    table: "invoices",
    name: "invoices_organization_id_not_null",
    expression: "(organization_id IS NOT NULL)",
  },
  {
    schema: "billing",
    table: "lines",
    name: "lines_currency_not_null",
    expression: "(currency IS NOT NULL)",
  },
  {
    schema: "public",
    table: "tasks",
    name: "tasks_points",
    expression: "(points > 0)",
  },
];

const database = (
  failing: ReadonlySet<string>,
  seen: string[],
): LiveDatabase => ({
  describe: "test",
  session: true,
  // SAFETY: the rule reads the rows it asks for, and these match its columns.
  query: (async (sql: string) => {
    seen.push(sql);

    if (sql.includes("pg_constraint")) {
      return CHECKS;
    }

    const table = [...failing].find((name) => sql.includes(name));

    return [{ failing: table !== undefined }];
  }) as LiveDatabase["query"],
});

const run = (
  db: DoctorContext["database"],
): ReturnType<(typeof NOT_VALID_RULES)[number]["check"]> =>
  // SAFETY: the rule reads only the database of the context.
  NOT_VALID_RULES[0]!.check({ database: db } as unknown as DoctorContext);

describe("BS236", () => {
  it("is registered", () => {
    expect(RULE_CODES).toContain("BS236");
  });

  it("offers to validate a clean check and points a failing one at db backfill", async () => {
    const seen: string[] = [];

    const findings = await run(database(new Set(['"billing"."lines"']), seen));

    expect(findings).toEqual([
      {
        message: expect.stringContaining(
          'no row fails it. Run `better-supabase doctor --fix` to validate it; then `alter table "public"."invoices" alter column "organization_id" set not null` needs no scan.',
        ),
        target: "public.invoices:invoices_organization_id_not_null",
        object: { kind: "table", schema: "public", name: "invoices" },
        fix: 'begin; set local statement_timeout = 0; alter table "public"."invoices" validate constraint "invoices_organization_id_not_null"; commit;',
      },
      {
        message: expect.stringContaining(
          "rows still fail it. Fill currency with `better-supabase db backfill billing.lines.currency --from <table.column> via <column>`",
        ),
        target: "billing.lines:lines_currency_not_null",
        object: { kind: "table", schema: "billing", name: "lines" },
      },
      expect.objectContaining({
        message: expect.stringMatching(/to validate it\.$/u),
        target: "public.tasks:tasks_points",
      }),
    ]);
    expect(seen[1]).toBe(
      'select exists (select 1 from "public"."invoices" where not ((organization_id IS NOT NULL))) as failing',
    );
  });

  it("skips a saved snapshot", async () => {
    expect(await run({ skipped: "a file" })).toEqual([]);
  });
});
