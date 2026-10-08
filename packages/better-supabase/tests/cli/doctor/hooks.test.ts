import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type {
  ExtrasHookFunction,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  hookGrantBlock,
  hookGrantProblems,
} from "../../../src/cli/doctor/hooks.ts";
import {
  type DoctorContext,
  RULES,
  runRules,
} from "../../../src/cli/doctor/rules.ts";
import { parseToml } from "../../../src/cli/supabase-toml.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import {
  stubProvider,
  withProvider,
} from "../../fixtures/authorization-provider.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";

const fixtureSnapshot = await parseSnapshot(fixture);
// The fixture's own hook writes user_role; each test adds the hook it needs.
const base: Snapshot = {
  ...fixtureSnapshot,
  extras: { ...fixtureSnapshot.extras, hooks: [] },
};

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
      dir: "supabase",
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

const OWN_HOOK = resolveConfig(
  {
    authorization: withProvider({
      tokenHook: {
        ...stubProvider.tokenHook,
        function: "rbac.custom_access_token_hook",
      },
    }),
  },
  "/project",
);

const only = (code: string) => RULES.filter((rule) => rule.code === code);
const ungranted = hookFn({ execute: ["anon"], schemaUsage: [] });

describe("hookGrantBlock", () => {
  it("points the provider's own hook at its grants command", () => {
    const problems = hookGrantProblems(
      context(withHook([ungranted]), { config: OWN_HOOK }),
    );
    expect(problems.map((problem) => problem.fix)).toEqual([
      {
        kind: "provider",
        name: "the authorization provider (stub)",
        command: "authz hook grants",
      },
    ]);
    expect(hookGrantBlock(problems, "migra").split("\n").slice(2)).toEqual([
      "",
      "-- rbac.custom_access_token_hook(event jsonb) ([auth.hook.custom_access_token]) is the hook of the authorization provider (stub): authz hook grants",
    ]);
  });

  it("points at a grants migration the database has not applied", () => {
    const path = "supabase/migrations/2_authz_hook_grants.sql";
    const problems = hookGrantProblems(
      context(withHook([ungranted]), {
        config: OWN_HOOK,
        sqlFiles: [
          {
            path,
            text: '-- authz: hook grants\ngrant execute on function "rbac"."custom_access_token_hook"(jsonb) to supabase_auth_admin;',
          },
        ],
      }),
    );
    expect(hookGrantBlock(problems, "migra").split("\n").at(-1)).toBe(
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

describe("BS308 tenant claim", () => {
  const hookDatabase = (
    claims: unknown,
    user: boolean = true,
  ): LiveDatabase => ({
    describe: "test",
    session: true,
    async query<R>(sql: string) {
      if (sql.includes("auth.users"))
        return [{ event: user ? "{}" : null }] as R[];
      if (sql.includes("pg_roles")) return [{ member: true }] as R[];
      if (sql.includes("as claims")) {
        if (claims instanceof Error) throw claims;
        return [{ claims }] as R[];
      }
      return [] as R[];
    },
  });
  const tenantConfig = resolveConfig(
    {
      sql: { modules: { tenant: {}, access: { activeTenant: "claim" } } },
    },
    "/project",
  );
  const run = (
    database: LiveDatabase,
    config = tenantConfig,
    hookUser: string | null = "u1",
  ) =>
    runRules(
      context(withHook([hookFn()]), {
        config,
        database,
        ...(hookUser ? { hookUser } : {}),
      }),
      only("BS308"),
    );

  it("warns when the hook's claims have no tenant claim", async () => {
    expect(await run(hookDatabase({ sub: "u1" }))).toMatchObject([
      {
        severity: "warning",
        message: expect.stringContaining("returns no `tenant_id` claim for u1"),
        target: "rbac.custom_access_token_hook(event jsonb):tenant_id",
      },
    ]);
    expect(await run(hookDatabase(JSON.stringify({ sub: "u1" })))).toHaveLength(
      1,
    );
  });

  it("accepts the claim at the top level or in app_metadata", async () => {
    expect(await run(hookDatabase({ tenant_id: "t1" }))).toEqual([]);
    expect(
      await run(hookDatabase({ app_metadata: { tenant_id: "t1" } })),
    ).toEqual([]);
  });

  it("skips other active-tenant sources, missing users, failures and runs without --as", async () => {
    const resolver = resolveConfig(
      {
        sql: { modules: { tenant: {}, access: { activeTenant: "resolver" } } },
      },
      "/project",
    );
    const empty = hookDatabase({});
    expect(await run(empty, resolver)).toEqual([]);
    expect(
      await run(
        empty,
        resolveConfig({ sql: { modules: ["tenant"] } }, "/project"),
      ),
    ).toEqual([]);
    expect(await run(empty, resolveConfig({}, "/project"))).toEqual([]);
    expect(await run(empty, tenantConfig, null)).toEqual([]);
    expect(await run(hookDatabase({}, false))).toEqual([]);
    expect(await run(hookDatabase(new Error("boom")))).toEqual([]);
    expect(await run(hookDatabase(null))).toHaveLength(1);
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
          "Measuring the hook's claims needs a direct database connection (local stack, $DATABASE_URL or --db-url-stdin).",
        target: "rbac.custom_access_token_hook(event jsonb):claims",
      },
    ]);
    expect(await run({ skipped: "a saved snapshot" })).toMatchObject([
      { message: expect.stringMatching(/--db-url-stdin\): a saved snapshot$/) },
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
    const event = queries.find((sql) =>
      sql.includes("better_supabase.hook_event"),
    );
    expect(event).toContain("'amr', jsonb_build_array(");
    expect(event).toContain("'iss', 'https://doctor.invalid/auth/v1'");
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
            dir: "supabase",
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
  it("skips hooks without a body and writers the provider does not own", async () => {
    const config = resolveConfig({ authorization: stubProvider }, "/project");
    expect(
      await runRules(context(withHook([hookFn()]), { config }), only("BS407")),
    ).toEqual([]);
    const lone = hookFn({
      source: "begin return jsonb_set(event, '{claims,roles}', r); end",
    });
    expect(
      await runRules(context(withHook([lone]), { config }), only("BS407")),
    ).toEqual([]);
    const writer = hookFn({
      source: "begin return jsonb_set(event, '{claims,memberships}', m); end",
    });
    expect(await runRules(context(withHook([writer])), only("BS407"))).toEqual(
      [],
    );
    expect(
      await runRules(context(withHook([writer]), { config }), only("BS407")),
    ).toHaveLength(1);
  });
});

describe("BS410 HTTP auth hooks", () => {
  const httpContext = (toml: string, document = parseToml(toml)) =>
    context(base, {
      configToml: {
        path: "supabase/config.toml",
        dir: "supabase",
        text: toml,
        document,
        parser: "smol-toml",
      },
    });
  const secret = `v1,whsec_${btoa("k".repeat(32))}`;

  it("reports an HTTP hook and checks a secret read from env()", async () => {
    const toml = `[auth.hook.send_email]
enabled = true
uri = "https://hooks.example.com/email"
secrets = "env(SEND_EMAIL_HOOK_SECRET)"
`;
    const unresolved = await runRules(httpContext(toml), only("BS410"));
    expect(unresolved).toMatchObject([
      {
        severity: "info",
        message: expect.stringContaining(
          "calls https://hooks.example.com/email over HTTP",
        ),
        location: { file: "supabase/config.toml", line: 1 },
      },
    ]);
    const interpolated = parseToml(
      toml.replace(
        "env(SEND_EMAIL_HOOK_SECRET)",
        `${secret}|v1,whsec_c2hvcnQ=`,
      ),
    );
    const findings = await runRules(
      httpContext(toml, interpolated),
      only("BS410"),
    );
    expect(findings.map((finding) => finding.severity)).toEqual([
      "info",
      "error",
    ]);
    expect(findings[1]?.message).toContain(
      "secret 2 decodes to 5 bytes; Standard Webhooks secrets are 24 to 64",
    );
    expect(JSON.stringify(findings)).not.toContain(secret);
  });

  it("flags a committed secret, a bad format, plain http and a missing secret", async () => {
    const toml = `[auth.hook.send_sms]
enabled = true
uri = "http://sms.example.com/hook"
secrets = "whsec_nope"

[auth.hook.mfa_verification_attempt]
enabled = true
uri = "http://127.0.0.1:3000/mfa"

[auth.hook.password_verification_attempt]
enabled = false
uri = "https://off.example.com"
`;
    const findings = await runRules(httpContext(toml), only("BS410"));
    expect(
      findings.map((finding) => [
        finding.target,
        finding.severity,
        finding.message,
      ]),
    ).toEqual([
      ["[auth.hook.send_sms]", "info", expect.stringContaining("over HTTP")],
      [
        "[auth.hook.send_sms]",
        "warning",
        expect.stringContaining("plain http"),
      ],
      [
        "[auth.hook.send_sms]",
        "warning",
        expect.stringContaining("is committed"),
      ],
      [
        "[auth.hook.send_sms]",
        "error",
        expect.stringContaining(
          "secret 1 is not in the `v1,whsec_<base64>` format",
        ),
      ],
      [
        "[auth.hook.mfa_verification_attempt]",
        "info",
        expect.stringContaining("127.0.0.1"),
      ],
      [
        "[auth.hook.mfa_verification_attempt]",
        "error",
        expect.stringContaining("has no `secrets`"),
      ],
    ]);
  });

  it("ignores Postgres function hooks", async () => {
    expect(await runRules(context(base), only("BS410"))).toEqual([]);
  });
});
