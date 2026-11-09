import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import {
  overrideHash,
  overridesIn,
} from "../../../src/cli/doctor/overrides.ts";
import { OWNERSHIP_RULES } from "../../../src/cli/doctor/ownership.ts";
import { RULES } from "../../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../../src/config/index.ts";

type Files = readonly { path: string; text: string }[];

const moduleFunction = `create or replace function better_supabase.finish_import_run(run uuid)
returns boolean
language plpgsql
as $$
begin
  return true;
end;
$$;`;

const moduleFile = {
  path: "supabase/schemas/_better_supabase/900_better_supabase_010_imports.sql",
  text: `-- @bsb-block imports@1\n${moduleFunction}\n`,
};

const copy = (hash: string, target = "better_supabase.finish_import_run") => ({
  path: "supabase/schemas/app/overrides.sql",
  text: `-- why this copy exists
-- @bsb-override-of ${target} ${hash}
-- more words
create or replace function better_supabase.finish_import_run(run uuid)
returns boolean language sql as $$ select false $$;
`,
});

const context = (
  sqlFiles: Files,
): Pick<DoctorContext, "config" | "sqlFiles" | "configToml"> => ({
  config: resolveConfig({}, "/p"),
  configToml: undefined,
  sqlFiles,
});

const current = overrideHash([moduleFunction]);

const bs394 = (files: Files) =>
  RULES.find((rule) => rule.code === "BS394")!.check(
    // SAFETY: BS394 reads only `sqlFiles`.
    context(files) as unknown as DoctorContext,
  );

describe("BS394 override drift", () => {
  it("hashes whitespace-insensitively", () => {
    expect(overrideHash([moduleFunction])).toBe(
      overrideHash([`${moduleFunction.replaceAll("\n", "\n  ")} `]),
    );
    expect(current).toMatch(/^[0-9a-f]{12}$/u);
  });

  it("reads the tag above an app function", () => {
    expect(overridesIn([copy(current)])).toEqual([
      {
        file: "supabase/schemas/app/overrides.sql",
        line: 2,
        of: "better_supabase.finish_import_run",
        hash: current,
        name: "better_supabase.finish_import_run",
      },
    ]);
  });

  it("accepts an override whose hash is current", async () => {
    expect(await bs394([moduleFile, copy(current)])).toEqual([]);
  });

  it("reports a changed module function with the new hash", async () => {
    const findings = await bs394([moduleFile, copy("000000000000")]);

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain(
      `@bsb-override-of better_supabase.finish_import_run ${current}`,
    );
    expect(findings[0]?.location).toEqual({
      file: "supabase/schemas/app/overrides.sql",
      line: 2,
    });
  });

  it("reports a target no module declares", async () => {
    const findings = await bs394([
      moduleFile,
      copy(current, "better_supabase.gone"),
    ]);

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain("no block module declares");
  });

  it("makes BS369 accept the tagged function only", async () => {
    const bs369 = OWNERSHIP_RULES.find((rule) => rule.code === "BS369")!;

    // SAFETY: BS369 reads only `sqlFiles` and `configToml`.
    const ctx = (files: Files) => context(files) as unknown as DoctorContext;

    expect(await bs369.check(ctx([moduleFile, copy(current)]))).toEqual([]);

    const untagged = {
      path: "supabase/schemas/app/overrides.sql",
      text: copy(current).text.replace(/^-- @bsb-override-of.*\n/mu, ""),
    };

    expect(await bs369.check(ctx([moduleFile, untagged]))).toHaveLength(1);
  });
});
