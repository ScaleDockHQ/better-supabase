import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { configIssues } from "../../src/cli/config-schema.ts";
import { loadConfig } from "../../src/cli/config.ts";
import { stubProvider } from "../fixtures/authorization-provider.ts";

const repo = join(import.meta.dirname, "../../../..");

describe("configIssues", () => {
  it("accepts a full config, generators included", () => {
    expect(
      configIssues({
        gen: {
          casing: "camel",
          codecs: { timestamptz: "instant", int8: "bigint" },
          tables: {
            audit_logs: { serviceRole: true },
            jobs: { exclude: true },
            invoices: { insertOptional: ["number"] },
          },
          generators: [{ name: "zod", generate: () => [] }],
        },
        plugins: { tenant: true, timestamps: true },
        database: { expose: { notes: ["select"], tags: { anon: ["select"] } } },
        tooling: { doctor: { ignore: ["BS303"], strict: true } },
        auth: { organization: { column: "org_id" } },
      }),
    ).toEqual([]);
  });

  it("accepts environment blocks and rejects nested ones", () => {
    expect(
      configIssues({
        gen: { tasks: ["types", "env"] },
        adapters: ["next"],
        $env: { staging: { tooling: { doctor: { strict: true } } } },
        $production: { tooling: { env: { output: ".env.production.local" } } },
      }),
    ).toEqual([]);
    expect(
      configIssues({
        gen: { tasks: ["lint"], watchInterval: 0 },
        adapters: ["express"],
        $ci: { $env: {} },
      }),
    ).toEqual([
      expect.stringMatching(/^adapters\.0: /),
      expect.stringMatching(/^gen\.tasks\.0: /),
      expect.stringMatching(/^gen\.watchInterval: /),
      expect.stringMatching(/^\$ci/),
    ]);
  });

  it("accepts specs outputs and rejects unknown levels and UIs", () => {
    expect(
      configIssues({
        api: {
          specs: {
            entry: "src/lib/api.ts",
            outputs: [
              {
                format: "openapi",
                version: "3.0",
                output: "legacy.yaml",
                serialize: "yaml",
              },
              { format: "openapi", ui: "redoc", overlays: ["docs.yaml"] },
            ],
            failOn: "never",
          },
        },
      }),
    ).toEqual([]);
    expect(
      configIssues({
        api: {
          specs: { outputs: [{ format: "", ui: "nope" }], failOn: "loud" },
        },
      }),
    ).toEqual([
      expect.stringMatching(/^api\.specs\.outputs\.0\.format: /),
      expect.stringMatching(/^api\.specs\.outputs\.0\.ui: /),
      expect.stringMatching(/^api\.specs\.failOn: /),
    ]);
  });

  it("accepts the entitlements claim shape and vector search ordering", () => {
    expect(
      configIssues({
        auth: {
          entitlements: { claim: { maxTenants: 20, keys: { exports: "x" } } },
        },
        database: {
          vectorSearch: {
            chunks: {
              column: "embedding",
              predicate: "t.expires_at > now()",
              boostMode: "add",
              order: "t.id desc",
            },
          },
        },
      }),
    ).toEqual([]);
    expect(configIssues({ auth: { entitlements: { claim: false } } })).toEqual(
      [],
    );
  });

  it("accepts column privileges in expose and rejects other strings", () => {
    expect(
      configIssues({
        database: {
          expose: {
            profiles: ["select", "update(username, first_name)"],
            notes: {
              anon: ["select(id,title)"],
              authenticated: ["insert(body)"],
            },
          },
        },
      }),
    ).toEqual([]);
    expect(
      configIssues({
        database: {
          expose: { profiles: ["update(username", "delete(id)", "truncate"] },
        },
      }),
    ).toEqual([
      expect.stringMatching(/^database\.expose\.profiles\.0: /),
      expect.stringMatching(/^database\.expose\.profiles\.1: /),
      expect.stringMatching(/^database\.expose\.profiles\.2: /),
    ]);
  });

  it("checks database.sql.workflow, buckets and gen.json the way their types do", () => {
    expect(
      configIssues({
        database: {
          sql: { workflow: "migrations" },
          buckets: {
            logos: {
              path: ["{organizationId}/logo.webp"],
              policy: { access: { read: "files.read", write: "files.write" } },
              lifecycle: {
                rules: [
                  { noncurrentVersionExpiration: { noncurrentDays: 30 } },
                ],
              },
            },
          },
        },
        gen: { json: { "notes.meta": { import: "./meta.ts#Meta" } } },
      }),
    ).toEqual([]);
    expect(
      configIssues({
        database: {
          sql: { workflow: "flyway" },
          buckets: { logos: { path: [], policy: "everyone" } },
        },
        gen: {
          json: { "notes.meta": { import: "./meta.ts#Meta", type: "Meta" } },
        },
      }),
    ).toEqual([
      expect.stringMatching(/^database\.sql\.workflow: /),
      expect.stringMatching(/^database\.buckets\.logos\.path: /),
      expect.stringMatching(/^database\.buckets\.logos\.policy: /),
      expect.stringMatching(/^gen\.json\.notes\.meta: Use \{ import \} or/),
    ]);
  });

  it("names the key path of every problem", () => {
    expect(
      configIssues({
        gen: {
          casing: "pascal",
          codecs: { timestamptz: "date" },
          generators: [{ name: "zod" }],
        },
        typo: true,
      }),
    ).toEqual([
      expect.stringMatching(/^gen\.casing: Invalid type/),
      expect.stringMatching(/^gen\.codecs\.timestamptz: Invalid type/),
      "gen.generators.0: must be a generator: { name, generate(input) }",
      expect.stringMatching(/^typo: Invalid key/),
    ]);
  });

  it("takes the access keys only under blocks.permissions", () => {
    expect(
      configIssues({
        blocks: {
          permissions: { model: "catalog", activeTenant: "claim" },
          organizations: {
            ownership: "adopt",
            options: { ownerRole: "owner" },
          },
        },
      }),
    ).toEqual([]);
    expect(
      configIssues({ blocks: { organizations: { model: "catalog" } } }),
    ).toEqual([
      expect.stringMatching(/^blocks\.organizations\.model: Invalid key/),
    ]);
  });
});

describe("committed configs", () => {
  it.each([
    "apps/examples/nextjs",
    "apps/examples/orpc-api",
    "apps/examples/hono-api",
    "apps/examples/vite-react",
    "apps/examples/mcp",
    "apps/examples/edge",
    "tests/validation-crm",
    "tests/validation-monorepo",
    "tests/validation-request-context",
    "tests/types/shared",
  ])("%s loads", async (dir) => {
    await expect(loadConfig(join(repo, dir))).resolves.toMatchObject({
      root: join(repo, dir),
    });
  });
});

describe("configIssues for authorization", () => {
  const issues = (over: Record<string, unknown>) =>
    configIssues({ auth: { authorization: { ...stubProvider, ...over } } });

  it("accepts the stub provider with the optional hooks", () => {
    expect(
      issues({
        functions: {
          ...stubProvider.functions,
          permissionsFor: "authz.permissions_for({user}, {tenant})",
          canApprove: "authz.can_approve({tool}, {tenant})",
        },
        approvals: { distinctApprover: true },
      }),
    ).toEqual([]);
    expect(configIssues({ auth: { claims: { memberships: "orgs" } } })).toEqual(
      [],
    );
  });

  it("accepts delegation scopes on the provider and the access module", () => {
    expect(
      issues({ delegation: { scopes: { "posts:write": ["posts.*"] } } }),
    ).toEqual([]);
    expect(
      configIssues({
        blocks: { permissions: { scopes: { "mcp:read": ["*"] } } },
      }),
    ).toEqual([]);
    expect(
      issues({ delegation: { scopes: { "posts:write": "posts.*" } } }).join(
        "\n",
      ),
    ).toMatch(/delegation/);
  });

  it("accepts isApprover, holdersOf, actorMayWrite and an operations table", () => {
    expect(
      issues({
        functions: {
          ...stubProvider.functions,
          isApprover: "authz.is_approver({kind}, {subject}, {tenant})",
          holdersOf: "authz.holders({permission}, {tenant})",
          actorMayWrite: "authz.actor_may_write()",
        },
        operations: {
          "workflow.node.http": {
            permission: "documents.write",
            meta: { risk: "high", effects: ["external"], title: "HTTP" },
          },
        },
      }),
    ).toEqual([]);
    expect(
      issues({ operations: { "mcp.tool.search": { permission: "" } } }).join(
        "\n",
      ),
    ).toMatch(/operations/);
    expect(
      issues({
        operations: {
          "mcp.tool.search": {
            permission: "documents.read",
            meta: { risk: "extreme" },
          },
        },
      }).join("\n"),
    ).toMatch(/risk/);
  });

  it("names a wrong apiVersion instead of listing every field", () => {
    expect(issues({ apiVersion: 2 })).toEqual([
      expect.stringMatching(
        /^auth\.authorization\.apiVersion: .*targets authorization provider API 2/,
      ),
    ]);
  });

  it("rejects inconsistent scopes and a fractional budget", () => {
    expect(
      issues({
        scopes: [
          { name: "organization", idType: "uuid", parent: "project" },
          { name: "project", idType: "numeric", parent: "organization" },
        ],
      }).join("\n"),
    ).toMatch(/idType/);
    expect(issues({ tenantScope: "team" }).join("\n")).toMatch(
      /tenantScope "team" is not a scope/,
    );
    expect(
      issues({
        tokenHook: {
          ...stubProvider.tokenHook,
          budget: { claims: ["memberships"], bytes: 1.5 },
        },
      }).join("\n"),
    ).toMatch(/bytes/);
    expect(
      issues({ decidingColumns: ["memberships.role"] }).join("\n"),
    ).toMatch(/Use schema\.table\.column/);
  });
});

describe("configIssues for a config written before 0.15", () => {
  it("names the group each moved key belongs to and the codemod", () => {
    expect(
      configIssues({
        casing: "camel",
        subjects: {},
        $production: { doctor: {} },
      }),
    ).toEqual([
      "casing: moved to `gen.casing` in 0.15; run `better-supabase codemod 0.15`",
      "subjects: moved to `records` in 0.15; run `better-supabase codemod 0.15`",
      "$production.doctor: moved to `tooling.doctor` in 0.15; run `better-supabase codemod 0.15`",
    ]);
  });
});
