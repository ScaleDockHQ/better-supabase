import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { SHIPPED_SHIM_RULES } from "../../../src/cli/doctor/shipped-shims.ts";
import { primeStatements } from "../../../src/cli/schema-reader/index.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const run = async (
  config: Parameters<typeof resolveConfig>[0],
  sqlFiles: DoctorContext["sqlFiles"] = [],
  provider?: object,
) => {
  await primeStatements(sqlFiles.map((file) => file.text));

  const resolved = resolveConfig(config, "/project");

  // SAFETY: the rule reads only `config` and `sqlFiles`.
  const context = {
    config: provider ? { ...resolved, authorization: provider } : resolved,
    sqlFiles,
  } as unknown as DoctorContext;

  return SHIPPED_SHIM_RULES[0]!.check(context) as { target: string }[];
};

describe("BS706", async () => {
  it("reports a seal trigger next to field-encryption", async () => {
    expect(
      (
        await run({
          blocks: ["field-encryption"],
          tooling: { doctor: { sealTriggers: ["public.seal"] } },
        })
      ).map((finding) => finding.target),
    ).toEqual(["tooling.doctor.sealTriggers"]);
    expect(
      await run({ tooling: { doctor: { sealTriggers: ["public.seal"] } } }),
    ).toEqual([]);
  });

  it("reports a decider where the provider has approverFor", async () => {
    const config = {
      blocks: { leave: { options: { decider: "public.can_decide" } } },
    };

    expect(await run(config)).toEqual([]);
    expect(
      (await run(config, [], { functions: { approverFor: "x.f({id})" } })).map(
        (finding) => finding.target,
      ),
    ).toEqual(["blocks.leave.options.decider"]);
  });

  it("reports approvals: false with standaloneApprovals", async () => {
    expect(
      (
        await run({
          blocks: {
            expenses: {
              options: { approvals: false, standaloneApprovals: true },
            },
          },
        })
      ).map((finding) => finding.target),
    ).toEqual(["blocks.expenses.options.approvals"]);
  });

  it("reports an app file that redefines a block function", async () => {
    const block = {
      path: "supabase/schemas/900_better_supabase_003_audit.sql",
      text: "-- @bsb-block audit\ncreate or replace function better_supabase.chain_link() returns trigger as $$ begin return new; end $$ language plpgsql;",
    };

    const app = {
      path: "supabase/schemas/overrides.sql",
      text: "create or replace function better_supabase.chain_link() returns trigger as $$ begin return new; end $$ language plpgsql;",
    };

    expect(
      (await run({}, [block, app])).map((finding) => finding.target),
    ).toEqual(["supabase/schemas/overrides.sql:chain_link"]);
    expect(await run({}, [block])).toEqual([]);
  });
});
