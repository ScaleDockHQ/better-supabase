import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type { TomlTable } from "../../../src/cli/supabase-toml.ts";

import { EDGE_FUNCTION_RULES } from "../../../src/cli/doctor/edge-functions.ts";
import { RULE_CODES } from "../../../src/cli/doctor/rules.ts";

const toml = (functions: TomlTable) => ({
  path: "supabase/config.toml",
  dir: "supabase",
  text: "",
  document: { functions },
  parser: "smol-toml" as const,
});

const run = (functions: TomlTable, files: Record<string, string>) =>
  EDGE_FUNCTION_RULES[0]!.check({
    configToml: toml(functions),
    functionFiles: Object.entries(files).map(([path, text]) => ({
      path,
      text,
    })),
    // SAFETY: BS395 reads only `configToml` and `functionFiles`.
  } as unknown as DoctorContext);

const user =
  "import { server } from './s.ts';\nexport default server({\n  auth: 'user',\n});\n";

describe("BS395 verify_jwt and auth: 'user'", () => {
  it("is registered", () => {
    expect(RULE_CODES).toContain("BS395");
  });

  it("flags a function that turns the gateway check off and expects a user", async () => {
    const findings = await run(
      { reports: { verify_jwt: false } },
      { "supabase/functions/reports/index.ts": user },
    );

    expect(findings).toMatchObject([
      {
        target: "[functions.reports] verify_jwt",
        location: { file: "supabase/functions/reports/index.ts", line: 3 },
      },
    ]);
  });

  it("leaves the mcp function, other functions and enabled checks alone", async () => {
    expect(
      await run(
        {
          mcp: { verify_jwt: false },
          hook: { verify_jwt: false },
          reports: { verify_jwt: true },
          other: {},
        },
        {
          "supabase/functions/mcp/index.ts": user,
          "supabase/functions/hook/index.ts": "export default () => {};",
          "supabase/functions/reports/index.ts": user,
        },
      ),
    ).toEqual([]);
  });

  it("does not match a function with a longer name", async () => {
    expect(
      await run(
        { report: { verify_jwt: false } },
        { "supabase/functions/reports/index.ts": user },
      ),
    ).toEqual([]);
  });
});
