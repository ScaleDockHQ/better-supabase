import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  type DoctorContext,
  RULES,
  runRules,
} from "../../../src/cli/doctor/rules.ts";
import { parseToml } from "../../../src/cli/supabase-toml.ts";
import {
  type BetterSupabaseConfig,
  resolveConfig,
} from "../../../src/config/index.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(fixture);

const CUSTOM: BetterSupabaseConfig = {
  sql: {
    modules: {
      access: {
        mode: "custom",
        model: "custom",
        functions: { can: "x()", tenantIdsWith: "y()", isPlatform: "z()" },
      },
    },
  },
};

function context(
  config: BetterSupabaseConfig,
  extra: Partial<DoctorContext> = {},
): DoctorContext {
  return {
    config: resolveConfig(config, "/project"),
    snapshot,
    configToml: undefined,
    envFiles: [],
    gitignore: "",
    sources: [],
    ...extra,
  };
}

const run = (ctx: DoctorContext, code = "BS307") =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === code),
  );

const database = (
  rows: readonly Record<string, string>[] | Error,
): LiveDatabase => ({
  describe: "test",
  session: true,
  query: <R>() =>
    rows instanceof Error
      ? Promise.reject(rows)
      : Promise.resolve(rows as unknown as R[]),
});

const fn = (name: string, args: string, returns = "boolean") => ({
  schema: "better_supabase",
  name,
  args,
  returns,
});

describe("BS307 custom module contracts", () => {
  it("passes when no module is in custom mode", async () => {
    expect(await run(context({ sql: { modules: ["access"] } }))).toEqual([]);
  });

  it("looks for create function in the SQL files without a database", async () => {
    const findings = await run(
      context(CUSTOM, {
        sqlFiles: [
          {
            path: "supabase/schemas/access.sql",
            text: `create or replace function better_supabase.can(scope text, id uuid, p text) returns boolean language sql as $$ select true $$;
create function "better_supabase"."tenant_ids_with"(p text) returns setof uuid language sql as $$ select null::uuid $$;`,
          },
        ],
      }),
    );
    const targets = findings.map((finding) => finding.target);
    expect(targets).not.toContain("better_supabase.can");
    expect(targets).not.toContain("better_supabase.tenant_ids_with");
    expect(targets).toContain("better_supabase.is_platform");
    expect(findings[0]).toMatchObject({
      code: "BS307",
      severity: "error",
      object: { kind: "function", schema: "better_supabase" },
    });
  });

  it("compares argument and return types with a database", async () => {
    const findings = await run(
      context(CUSTOM, {
        database: database([
          fn("can", "text, uuid, text"),
          fn("tenant_ids_with", "text", "uuid"),
          fn("is_platform", "text", "text"),
          fn("can_user", "uuid, text"),
          fn("permission_claims", "uuid", "jsonb"),
        ]),
      }),
    );
    expect(
      findings.map((finding) => [finding.target, finding.message]),
    ).toEqual([
      [
        "better_supabase.is_platform",
        expect.stringContaining(
          "returns text; the access contract expects boolean",
        ),
      ],
      [
        "better_supabase.can_user",
        expect.stringContaining(
          "takes (uuid, text); the access contract calls it with (uuid, text, uuid, text)",
        ),
      ],
      ["better_supabase.can_assign", expect.stringContaining("doesn't exist")],
      ["better_supabase.member_can", expect.stringContaining("doesn't exist")],
      [
        "better_supabase.can_assign_as",
        expect.stringContaining("doesn't exist"),
      ],
    ]);
  });

  it("reports a failed query as info", async () => {
    const findings = await run(
      context(CUSTOM, { database: database(new Error("offline")) }),
    );
    expect(findings).toMatchObject([
      { severity: "info", message: expect.stringContaining("offline") },
    ]);
  });
});

const toml = (text: string): DoctorContext["configToml"] => ({
  path: "supabase/config.toml",
  dir: "supabase",
  text,
  document: parseToml(text),
  parser: "smol-toml",
});

describe("BS325 audit user-session reads", () => {
  it("warns when the app lists the log and the module stays service_role only", async () => {
    const findings = await run(
      context(
        { sql: { modules: { audit: {} } } },
        { sources: [{ path: "src/audit.ts", text: "await audit.list()" }] },
      ),
      "BS325",
    );
    expect(findings).toMatchObject([{ code: "BS325" }]);
  });

  it("passes when authenticated can read", async () => {
    const findings = await run(
      context(
        {
          sql: {
            modules: {
              audit: {
                options: {
                  readPolicy: true,
                  eventRoles: ["authenticated", "service_role"],
                },
              },
            },
          },
        },
        { sources: [{ path: "src/audit.ts", text: "await audit.list()" }] },
      ),
      "BS325",
    );
    expect(findings).toEqual([]);
  });
});

describe("BS326 secret key", () => {
  it("warns when deleteAccount is used without a secret key", async () => {
    const findings = await run(
      context(
        {},
        {
          sources: [
            { path: "src/user.ts", text: "await server.deleteAccount(id)" },
          ],
        },
      ),
      "BS326",
    );
    expect(findings).toMatchObject([{ code: "BS326" }]);
  });
});

describe("BS327 aal2 without MFA", () => {
  it("warns when requireAal aal2 runs and totp is off", async () => {
    const findings = await run(
      context(
        {},
        {
          configToml: toml("[auth.mfa.totp]\nenroll_enabled = false\n"),
          sources: [
            { path: "src/proxy.ts", text: "protect: requireAal('aal2')" },
          ],
        },
      ),
      "BS327",
    );
    expect(findings).toMatchObject([{ code: "BS327" }]);
  });
});
