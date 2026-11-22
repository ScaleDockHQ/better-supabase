import { describe, expect, it } from "vitest";

import { resolveConfig } from "../../src/config/index.ts";
import { restatedEntries } from "../../src/config/restated.ts";

const tables = {
  memberships: {
    columns: {
      tenant: "tenant_id",
      user: "user_id",
      lastUsedAt: "last_used_at",
    },
    optional: ["lastUsedAt"],
  },
};

const input = (blocks: object, extra: object = {}) => ({
  // SAFETY: the fixtures set only the keys restatedEntries reads.
  blocks: blocks as never,
  defaultColumns: () => tables,
  ...extra,
});

const paths = (entries: ReturnType<typeof restatedEntries>) =>
  entries.map((entry) => `${entry.kind}:${entry.path}`);

const report = (blocks: object, extra: object = {}) =>
  paths(restatedEntries(input(blocks, extra)));

describe("restatedEntries gen.functions", () => {
  const declared = (name: string) =>
    name === "set_platform_setting" ? true : undefined;

  it("reports a notNull the block declares", () => {
    expect(
      report(
        {},
        {
          genFunctions: {
            set_platform_setting: { notNull: true },
            own_function: { notNull: true },
            "public.other": { notNull: ["a"] },
          },
          blockNotNull: declared,
        },
      ),
    ).toEqual(["notNull:gen.functions.set_platform_setting.notNull"]);
  });

  it("keeps a notNull that differs from the block's", () => {
    expect(
      restatedEntries(
        input(
          {},
          {
            genFunctions: { set_platform_setting: { notNull: [] } },
            blockNotNull: declared,
          },
        ),
      ),
    ).toEqual([]);
  });
});

describe("restatedEntries", () => {
  it("reports an identity mapping of an optional column", () => {
    expect(
      report({
        memberships: {
          columns: { memberships: { lastUsedAt: "last_used_at" } },
        },
      }),
    ).toEqual(["identity:blocks.memberships.columns.memberships.lastUsedAt"]);
  });

  it("keeps a required identity mapping and a renamed column", () => {
    expect(
      restatedEntries(
        input({
          memberships: {
            columns: {
              memberships: { lastUsedAt: "last_used_at", user: "uid" },
            },
            requiredColumns: { memberships: ["lastUsedAt"] },
          },
        }),
      ),
    ).toEqual([]);
  });

  it("reports a null for a column the view lacks", () => {
    expect(
      report(
        {},
        {
          nulls: [
            {
              block: "tags",
              logical: "tags",
              column: "rank",
              name: "rank",
              view: "public.tags",
            },
          ],
        },
      ),
    ).toEqual(["null:blocks.tags.columns.tags.rank"]);
  });

  it("reports empty maps", () => {
    expect(report({ tags: { values: {}, columns: { tags: {} } } })).toEqual([
      "empty:blocks.tags.values",
      "empty:blocks.tags.columns.tags",
    ]);
  });

  it("reports a tenant column equal to sql.tenantColumn only", () => {
    const blocks = {
      teams: { columns: { memberships: { tenant: "org_id" } } },
      tags: { columns: { memberships: { tenant: "account_id" } } },
    };

    expect(report(blocks, { sqlTenantColumn: "org_id" })).toEqual([
      "tenant:blocks.teams.columns.memberships.tenant",
    ]);
  });

  it("reports the claims hook equal to the provider's token hook", () => {
    const provider = {
      name: "stub",
      tokenHook: { function: "authz.access_token_hook" },
      // SAFETY: only the fields restatedEntries reads are set.
    } as never;

    expect(
      report(
        {
          impersonation: { options: { claimsHook: "authz.access_token_hook" } },
        },
        { provider },
      ),
    ).toEqual(["provider:blocks.impersonation.options.claimsHook"]);
  });

  it("reports permissions equal to the provider's actionKeys", () => {
    const provider = {
      name: "stub",
      actionKeys: {
        blocks: { audit: { read: "audit.read", export: "audit.export" } },
        recordTypes: { note: { read: "note.read" } },
      },
      // SAFETY: only the fields restatedEntries reads are set.
    } as never;

    expect(
      paths(
        restatedEntries({
          ...input(
            { audit: { permissions: { read: "audit.read", export: "mine" } } },
            { provider },
          ),
          subjects: { note: { permissions: { read: "note.read" } } },
        }),
      ),
    ).toEqual([
      "provider:blocks.audit.permissions.read",
      "provider:subjects.note.permissions.read",
    ]);
  });
});

describe("project defaults", () => {
  const config = resolveConfig(
    {
      database: { sql: { audit: false, api: "api" } },
      blocks: {
        tags: { audit: false },
        tasks: { api: "api" },
        notes: { audit: true, api: "other" },
        labels: {},
      },
    },
    "/project",
  );

  it("fills sql.audit into blocks that leave it unset", () => {
    expect(config.blocks["labels"]?.audit).toBe(false);
    expect(config.blocks["notes"]?.audit).toBe(true);
    expect(config.sql.blockDefaults?.audit).toBe(false);
  });

  it("lists the entries that repeat sql.api or sql.audit", () => {
    expect(report({}, { restatedDefaults: config.restatedDefaults })).toEqual([
      "default:blocks.tags.audit",
      "default:blocks.tasks.api",
    ]);
  });
});

describe("restatedEntries normal forms", () => {
  const provider = {
    name: "authz",
    apiVersion: 1,
    suspension: {
      tenant: {
        table: "public.orgs",
        id: "id",
        status: "status",
        active: ["live", "trial"],
      },
      user: "public.profiles.disabled_at",
      userKey: "auth_id",
    },
    roleSources: [
      {
        table: "public.members",
        role: {
          column: "role_id",
          through: {
            table: "public.roles",
            id: "id",
            column: "key",
            where: "{row}.scope = 'tenant'",
          },
        },
      },
    ],
    platformRoles: {
      table: "public.staff",
      user: "user_id",
      role: "role",
      canAssign: "authz.can_assign({role})",
    },
  };

  const found = (blocks: object) => report(blocks, { provider });

  it("ignores key order and the order of active values", () => {
    expect(
      found({
        permissions: {
          disabled: {
            tenant: {
              active: ["trial", "live"],
              status: "status",
              id: "id",
              table: "public.orgs",
            },
          },
        },
      }),
    ).toEqual(["provider:blocks.permissions.disabled.tenant"]);
  });

  it("compares a roleThrough where and a canAssign token by token", () => {
    expect(
      found({
        memberships: {
          options: {
            roleThrough: {
              table: "public.roles",
              id: "id",
              column: "key",
              where: "{row}.scope   =   'tenant'",
            },
          },
        },
        invitations: {
          options: {
            platformRoles: {
              table: "public.staff",
              user: "user_id",
              role: "role",
              canAssign: "AUTHZ.CAN_ASSIGN( {role} )",
            },
          },
        },
      }),
    ).toEqual([
      "provider:blocks.invitations.options.platformRoles",
      "provider:blocks.memberships.options.roleThrough",
    ]);
  });

  it("keeps a string literal that differs in case", () => {
    expect(
      found({
        memberships: {
          options: {
            roleThrough: {
              table: "public.roles",
              id: "id",
              column: "key",
              where: "{row}.scope = 'Tenant'",
            },
          },
        },
      }),
    ).toEqual([]);
  });

  it("keeps an active row apart from a column string", () => {
    expect(
      found({
        permissions: {
          disabled: {
            user: {
              table: "public.profiles",
              id: "auth_id",
              disabledAt: "disabled_at",
            },
          },
        },
      }),
    ).toEqual([]);
  });

  it("reports a claims hook that differs only in case", () => {
    expect(
      report(
        { impersonation: { options: { claimsHook: "Authz.Hook" } } },
        { provider: { ...provider, tokenHook: { function: "authz.hook" } } },
      ),
    ).toEqual(["provider:blocks.impersonation.options.claimsHook"]);
  });
});

describe("restatedEntries activeTenant", () => {
  it("reports the default and keeps the others", () => {
    expect(report({ permissions: { activeTenant: "resolver" } })).toEqual([
      "default:blocks.permissions.activeTenant",
    ]);
    expect(
      restatedEntries(input({ permissions: { activeTenant: "claim" } })),
    ).toEqual([]);
  });
});
