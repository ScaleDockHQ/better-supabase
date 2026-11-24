import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { primeDoctorFacts } from "../../../src/cli/doctor/prime.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { codeStatementsOf } from "../../../src/cli/schema-reader/index.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(fixture);

const dispatch = (name: string, arms: readonly string[]): string =>
  `create or replace function public.${name}(entity text)
returns void language plpgsql as $$
begin
  case entity
    ${arms.map((arm) => `when '${arm}' then null;`).join("\n    ")}
    else null;
  end case;
end $$;`;

const migrations = Array.from({ length: 200 }, (_, index) => ({
  path: `supabase/migrations/2026${String(index).padStart(10, "0")}_step.sql`,
  text: dispatch(`step_${String(index)}`, ["alpha", "beta"]),
}));

const schema = {
  path: "supabase/schemas/dispatch.sql",
  text: dispatch("step_199", ["alpha", "beta", "gamma"]),
};

const grant = {
  path: "supabase/migrations/20270101000000_hook.sql",
  text: "grant execute on function public.hook(jsonb) to supabase_auth_admin;",
};

const context = (): DoctorContext => ({
  config: resolveConfig({}, "/project"),
  snapshot,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  sqlFiles: [schema, ...migrations, grant],
});

describe("primeDoctorFacts", () => {
  it("keeps code tokens for schema files and hook grants, not the migration history", async () => {
    await primeDoctorFacts(context());

    expect(codeStatementsOf(schema.text)).toHaveLength(1);
    expect(codeStatementsOf(grant.text)).toHaveLength(1);
    expect(() => codeStatementsOf(migrations[0]!.text)).toThrow(
      /has not tokenized this text/,
    );
  });

  it("still reads each migration's dispatch arms for BS629", async () => {
    const findings = await runRules(
      context(),
      RULES.filter((rule) => rule.code === "BS629"),
    );

    expect(findings.map((finding) => finding.message)).toEqual([
      "The newest migration of step_199 drops dispatch arms the schema file still has: gamma.",
    ]);
  });
});
