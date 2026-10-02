import { resolveConfig } from "better-supabase/config";
import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../src/doctor/live.ts";
import type {
  ExtrasHookFunction,
  Snapshot,
} from "../../src/introspect/types.ts";
import type { PermdockProject } from "../../src/permdock.ts";

import { parseSnapshot } from "../../src/commands/snapshot.ts";
import { hookGrantBlock, hookGrantProblems } from "../../src/doctor/hooks.ts";
import { type DoctorContext, RULES, runRules } from "../../src/doctor/rules.ts";
import { parseManifest } from "../../src/permdock.ts";
import { parseToml } from "../../src/supabase-toml.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";
import manifest from "../fixtures/permdock.manifest.json" with { type: "json" };

const base = parseSnapshot(fixture);

const HOOK_TOML = `[auth.hook.custom_access_token]
enabled = true
uri = "pg-functions://postgres/rbac/custom_access_token_hook"
`;

const hookFn = (
  overrides: Partial<ExtrasHookFunction> = {},
): ExtrasHookFunction => ({
  schema: "rbac",
  name: "custom_access_token_hook",
  signature: "event jsonb",
  language: "plpgsql",
  volatility: "stable",
  securityDefiner: false,
  settings: { search_path: "" },
  execute: ["supabase_auth_admin"],
  publicExecute: false,
  schemaUsage: ["supabase_auth_admin"],
  ...overrides,
});

const withHook = (functions: ExtrasHookFunction[]): Snapshot => ({
  ...base,
  extras: {
    ...base.extras,
    hooks: [
      {
        hook: "custom_access_token",
        schema: "rbac",
        name: "custom_access_token_hook",
        functions,
      },
    ],
  },
});

function context(
  snapshot: Snapshot,
  extra: Partial<DoctorContext> = {},
): DoctorContext {
  return {
    config: resolveConfig({}, "/project"),
    snapshot,
    configToml: {
      path: "supabase/config.toml",
      text: HOOK_TOML,
      document: parseToml(HOOK_TOML),
      parser: "smol-toml",
    },
    envFiles: [],
    gitignore: "",
    sources: [],
    ...extra,
  };
}

const PERMDOCK: PermdockProject = {
  config: "permdock.config.ts",
  manifestPath: "permdock.manifest.json",
  manifest: parseManifest(manifest),
  catalogPath: "permissions.catalog.json",
  problems: [],
};

const only = (code: string) => RULES.filter((rule) => rule.code === code);
const ungranted = hookFn({ execute: ["anon"], schemaUsage: [] });

describe("hookGrantBlock", () => {
  it("points PermDock's own hook at its grants command", () => {
    const permdock: PermdockProject = {
      ...PERMDOCK,
      manifest: {
        ...PERMDOCK.manifest!,
        hook: { schema: "rbac", function: "custom_access_token_hook" },
      },
    };
    const problems = hookGrantProblems(
      context(withHook([ungranted]), { permdock }),
    );
    expect(problems.map((problem) => problem.fix)).toEqual([
      { kind: "permdock" },
    ]);
    expect(hookGrantBlock(problems).split("\n").slice(2)).toEqual([
      "",
      "-- rbac.custom_access_token_hook(event jsonb) ([auth.hook.custom_access_token]) is PermDock's hook: permdock supabase hook generate --grants-out supabase/migrations/<timestamp>_permdock_hook_grants.sql",
    ]);
  });

  it("points at a grants migration the database has not applied", () => {
    const path = "supabase/migrations/2_permdock_hook_grants.sql";
    const problems = hookGrantProblems(
      context(withHook([ungranted]), {
        sqlFiles: [
          {
            path,
            text: '-- permdock:grants v1 schema=rbac\ngrant execute on function "rbac"."custom_access_token_hook"(jsonb) to supabase_auth_admin;',
          },
        ],
      }),
    );
    expect(hookGrantBlock(problems).split("\n").at(-1)).toBe(
      `-- rbac.custom_access_token_hook(event jsonb) ([auth.hook.custom_access_token]): ${path} grants it; run \`supabase migration up\`.`,
    );
  });

  it("finds no problems without a config.toml", () => {
    expect(
      hookGrantProblems({
        ...context(withHook([ungranted])),
        configToml: undefined,
      }),
    ).toEqual([]);
  });
});

describe("BS405 --as", () => {
  it("needs a direct session to call the hook", async () => {
    const run = (database?: DoctorContext["database"]) =>
      runRules(
        context(withHook([hookFn()]), {
          hookUser: "u1",
          ...(database ? { database } : {}),
        }),
        only("BS405"),
      );
    expect(await run()).toMatchObject([
      {
        severity: "info",
        message:
          "Measuring the hook's claims needs a direct database connection (local stack or --db-url).",
        target: "rbac.custom_access_token_hook(event jsonb):claims",
      },
    ]);
    expect(await run({ skipped: "a saved snapshot" })).toMatchObject([
      { message: expect.stringMatching(/--db-url\): a saved snapshot$/) },
    ]);
    const management: LiveDatabase = {
      describe: "api",
      session: false,
      query: () => Promise.resolve([]),
    };
    expect(await run(management)).toMatchObject([{ severity: "info" }]);
  });

  it("reports a hook call that fails, and rolls back", async () => {
    const queries: string[] = [];
    const database: LiveDatabase = {
      describe: "test",
      session: true,
      async query<R>(sql: string) {
        queries.push(sql);
        if (
          sql.includes("better_supabase.hook_event") &&
          sql.includes("auth.users")
        )
          return [{ event: "{}" }] as R[];
        if (sql.includes("pg_roles")) return [{ member: false }] as R[];
        if (sql.includes("octet_length"))
          throw new Error(
            "function rbac.custom_access_token_hook does not exist",
          );
        return [] as R[];
      },
    };
    const findings = await runRules(
      context(withHook([hookFn()]), { database, hookUser: "u1" }),
      only("BS405"),
    );
    expect(findings).toMatchObject([
      {
        severity: "warning",
        message:
          "Calling rbac.custom_access_token_hook(event jsonb) for u1 failed: function rbac.custom_access_token_hook does not exist",
        object: { kind: "function", name: "custom_access_token_hook" },
      },
    ]);
    expect(queries).not.toContain("set local role supabase_auth_admin");
    expect(queries.at(-1)).toBe("rollback");
  });

  it("checks only the custom access token hook", async () => {
    const snap: Snapshot = {
      ...base,
      extras: {
        ...base.extras,
        hooks: [
          {
            hook: "send_email",
            schema: "rbac",
            name: "custom_access_token_hook",
            functions: [hookFn({ volatility: "volatile" })],
          },
        ],
      },
    };
    const toml = `[auth.hook.send_email]\nenabled = true\nuri = "pg-functions://postgres/rbac/custom_access_token_hook"\n`;
    expect(
      await runRules(
        context(snap, {
          configToml: {
            path: "supabase/config.toml",
            text: toml,
            document: parseToml(toml),
            parser: "smol-toml",
          },
        }),
        only("BS405"),
      ),
    ).toEqual([]);
  });
});

describe("BS407", () => {
  it("reports an unreadable manifest instead of asking for one", async () => {
    const broken: PermdockProject = {
      config: "permdock.config.ts",
      manifestPath: "permdock.manifest.json",
      catalogPath: "permissions.catalog.json",
      problems: [
        "permdock.manifest.json: Unexpected token",
        "permissions.catalog.json: missing",
      ],
    };
    expect(
      await runRules(context(base, { permdock: broken }), only("BS407")),
    ).toEqual([
      expect.objectContaining({
        severity: "info",
        message:
          "Could not read PermDock's manifest: permdock.manifest.json: Unexpected token",
        target: "permdock.manifest.json",
      }),
    ]);
  });

  it("reads the claims PermDock's hook adds from the marker when the manifest lists none", async () => {
    const permdock: PermdockProject = {
      ...PERMDOCK,
      manifest: {
        ...PERMDOCK.manifest!,
        hook: { schema: "public", function: "permdock_hook" },
        claims: [{ name: "roles", source: "permdock" }],
      },
    };
    const marker = {
      path: "supabase/schemas/040_permdock_hook.sql",
      text: "-- permdock:hook v1 schema=public claims=roles,tenant_id,features,attrs\ncreate or replace function public.permdock_hook(event jsonb)",
    };
    const wrapper = hookFn({
      source:
        "begin event := public.permdock_hook(event); return jsonb_set(event, '{claims,features}', f); end",
    });
    const findings = await runRules(
      context(withHook([wrapper]), { permdock, sqlFiles: [marker] }),
      only("BS407"),
    );
    expect(findings).toHaveLength(1);
    expect(findings[0]!.message).toContain(
      "writes features, and permdock.config.ts says PermDock owns those claims (its hook already writes features through supabase.hook.claims)",
    );
    expect(findings[0]!.location).toEqual({
      file: "supabase/config.toml",
      line: 1,
    });
    const plain = hookFn({
      source: "begin return jsonb_set(event, '{claims,features}', f); end",
    });
    expect(
      await runRules(
        context(withHook([plain]), { permdock, sqlFiles: [marker] }),
        only("BS407"),
      ),
    ).toEqual([]);
  });

  it("skips hooks without a body and writers PermDock does not own", async () => {
    expect(
      await runRules(
        context(withHook([hookFn()]), { permdock: PERMDOCK }),
        only("BS407"),
      ),
    ).toEqual([]);
    const lone = hookFn({
      source: "begin return jsonb_set(event, '{claims,roles}', r); end",
    });
    expect(await runRules(context(withHook([lone])), only("BS407"))).toEqual(
      [],
    );
  });
});
