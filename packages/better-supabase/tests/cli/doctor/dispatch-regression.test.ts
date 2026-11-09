import { describe, expect, it } from "vitest";

import { dispatchRegressions } from "../../../src/cli/doctor/dispatch-regression.ts";

const schema = (arms: readonly string[]): string =>
  `create function public.import_apply_batch(run uuid)
returns jsonb language plpgsql as $$
begin
  case entity
    ${arms.map((arm) => `when '${arm}' then null;`).join("\n    ")}
    else null;
  end case;
end $$;`;

const migration = (name: string, body: string) => ({
  path: `supabase/migrations/${name}.sql`,
  text: body,
});

describe("BS625 dispatch arms", () => {
  it("names the arms a later migration dropped", () => {
    const findings = dispatchRegressions(
      [
        {
          path: "supabase/schemas/overrides.sql",
          text: schema(["alpha", "beta"]),
        },
        migration("20261107000000_old", schema(["alpha", "beta"])),
        migration("20261107155205_later", schema(["alpha"])),
      ],
      [],
    );

    expect(findings.map((finding) => finding.message).join("\n")).toContain(
      "beta",
    );
  });

  it("passes once the migration dispatches every schema arm", () => {
    const findings = dispatchRegressions(
      [
        {
          path: "supabase/schemas/overrides.sql",
          text: schema(["alpha", "beta"]),
        },
        migration("20261107170100_sync", schema(["alpha", "beta"])),
      ],
      [],
    );

    expect(findings).toEqual([]);
  });

  it("names a configured entity the override does not dispatch", () => {
    const findings = dispatchRegressions(
      [{ path: "supabase/schemas/overrides.sql", text: schema(["invoice"]) }],
      ["invoice", "quote"],
    );

    expect(findings.map((finding) => finding.message).join("\n")).toContain(
      "quote",
    );
  });
});
