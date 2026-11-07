import { describe, expect, it } from "vitest";

import {
  SHIM_RULES,
  SHIMS,
  shimFindings,
} from "../../../src/cli/doctor/shims.ts";

const source = (text: string) => ({ sources: [{ path: "app/x.ts", text }] });

const find = (code: string) => {
  const shim = SHIMS.find((entry) => entry.code === code);

  if (!shim) {
    throw new Error(`no shim ${code}`);
  }

  return shim;
};

const HIT: Readonly<Record<string, string>> = {
  BS612:
    'import { bsb } from "@/lib/supabase";\n// proxy\ncookies: { setAll(list) {} }',
  BS613:
    'import { bsb } from "@/lib/supabase";\nawait bsb.bootstrap({});\nawait supabase.auth.getUser();',
  BS614:
    'import { bsb } from "@/lib/supabase";\nawait bsb.bootstrap({});\nseedAuthzVersion(1);',
  BS615:
    'import { bsb } from "@/lib/supabase";\ncomments.filter((c) => !c.deletedAt);',
  BS616: 'import { bsb } from "@/lib/supabase";\nhydrateStoredComments(rows);',
  BS617: 'import { bsb } from "@/lib/supabase";\nwithPublicPolicyRoles(q);',
  BS618:
    'import { bsb } from "@/lib/supabase";\nif (error.code === "23505") {}',
  BS619:
    'import { bsb } from "@/lib/supabase";\nsupport.start({ source: "cookie", token });',
  BS620:
    'import { bsb } from "@/lib/supabase";\nawait db.from("organizations").update({ settings: { ...old, theme } });',
};

describe("doctor shims", () => {
  it("lists nine shims with one rule each", () => {
    expect(SHIMS).toHaveLength(9);
    expect(SHIM_RULES.map((rule) => rule.code)).toEqual(
      SHIMS.map((shim) => shim.code),
    );
  });

  it.each(Object.entries(HIT))("%s matches its shim", (code, text) => {
    const findings = shimFindings(source(text), find(code));

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain(find(code).since);
  });

  it("ignores files that never name the library", () => {
    const findings = shimFindings(
      source("withPublicPolicyRoles(q)"),
      find("BS617"),
    );

    expect(findings).toEqual([]);
  });
});
