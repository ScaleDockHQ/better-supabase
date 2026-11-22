import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { SHIPPED_SHIM_RULES } from "../../../src/cli/doctor/shipped-shims.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const run = (
  config: Parameters<typeof resolveConfig>[0],
  sqlFiles: DoctorContext["sqlFiles"] = [],
  provider?: object,
) => {
  const resolved = resolveConfig(config, "/project");

  // SAFETY: the rule reads only `config` and `sqlFiles`.
  const context = {
    config: provider ? { ...resolved, authorization: provider } : resolved,
    sqlFiles,
  } as unknown as DoctorContext;

  return SHIPPED_SHIM_RULES[0]!.check(context) as { target: string }[];
};

describe("BS706", () => {
  it("reports a seal trigger next to field-encryption", () => {
    expect(
      run({
        blocks: ["field-encryption"],
        tooling: { doctor: { sealTriggers: ["public.seal"] } },
      }).map((finding) => finding.target),
    ).toEqual(["tooling.doctor.sealTriggers"]);
    expect(
      run({ tooling: { doctor: { sealTriggers: ["public.seal"] } } }),
    ).toEqual([]);
  });

  it("reports a decider where the provider has approverFor", () => {
    const config = {
      blocks: { leave: { options: { decider: "public.can_decide" } } },
    };

    expect(run(config)).toEqual([]);
    expect(
      run(config, [], { functions: { approverFor: "x.f({id})" } }).map(
        (finding) => finding.target,
      ),
    ).toEqual(["blocks.leave.options.decider"]);
  });

  it("reports approvals: false with standaloneApprovals", () => {
    expect(
      run({
        blocks: {
          expenses: {
            options: { approvals: false, standaloneApprovals: true },
          },
        },
      }).map((finding) => finding.target),
    ).toEqual(["blocks.expenses.options.approvals"]);
  });

  it("reports an app file that redefines a block function", () => {
    const block = {
      path: "supabase/schemas/900_better_supabase_003_audit.sql",
      text: "-- @bsb-block audit\ncreate or replace function better_supabase.chain_link() returns trigger as $$ begin return new; end $$ language plpgsql;",
    };

    const app = {
      path: "supabase/schemas/overrides.sql",
      text: "create or replace function better_supabase.chain_link() returns trigger as $$ begin return new; end $$ language plpgsql;",
    };

    expect(run({}, [block, app]).map((finding) => finding.target)).toEqual([
      "supabase/schemas/overrides.sql:chain_link",
    ]);
    expect(run({}, [block])).toEqual([]);
  });
});
