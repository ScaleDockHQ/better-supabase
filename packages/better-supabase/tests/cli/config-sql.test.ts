import { describe, expect, it } from "vitest";

import {
  checkConfigSql,
  configSqlFragments,
} from "../../src/cli/config-sql.ts";
import { resolveConfig } from "../../src/config/index.ts";

const provider = (functions: Record<string, string>) =>
  resolveConfig(
    {
      auth: {
        authorization: {
          apiVersion: 1,
          name: "stub",
          scopes: [{ name: "organization", idType: "uuid" }],
          tenantScope: "organization",
          functions: {
            idsWith: "authz.ids_{scope}({permission})",
            isPlatform: "authz.is_platform({permission})",
            ...functions,
          },
        },
      },
    },
    "/project",
  );

describe("config SQL fragments", () => {
  it("lists the provider's function templates by config key", () => {
    expect(configSqlFragments(provider({})).map((each) => each.path)).toEqual([
      "authorization.functions.idsWith",
      "authorization.functions.isPlatform",
    ]);
  });

  it("accepts templates with placeholders", async () => {
    await expect(checkConfigSql(provider({}))).resolves.toBeUndefined();
  });

  it("names the config key of a template that is not SQL", async () => {
    const result = await checkConfigSql(
      provider({ canAssign: "authz.can_assign({user}, {role}" }),
    );

    expect(result?.code).toBe(1);
    expect(result?.error).toContain(
      "authorization.functions.canAssign is not valid SQL",
    );
  });
});

describe("every config key that holds SQL", () => {
  const withAuth = (extra: Record<string, unknown>) =>
    resolveConfig(
      {
        auth: {
          authorization: {
            apiVersion: 1,
            name: "stub",
            scopes: [{ name: "organization", idType: "uuid" }],
            tenantScope: "organization",
            functions: {
              idsWith: "authz.ids_{scope}({permission})",
              isPlatform: "authz.is_platform({permission})",
            },
            ...extra,
          },
        },
      },
      "/project",
    );

  const bad = async (config: ReturnType<typeof resolveConfig>) =>
    (await checkConfigSql(config))?.error ?? "";

  it("lists vectorSearch boost, predicate and order by key", () => {
    const config = resolveConfig(
      {
        database: {
          vectorSearch: {
            "public.docs": {
              column: "embedding",
              boost: "t.priority",
              predicate: "t.expires_at > now()",
              order: "t.created_at desc",
            },
          },
        },
      },
      "/project",
    );

    expect(configSqlFragments(config).map((each) => each.path)).toEqual([
      "vectorSearch.public.docs.boost",
      "vectorSearch.public.docs.predicate",
      "vectorSearch.public.docs.order",
    ]);
  });

  it("names the config key of a bad vectorSearch predicate, boost or order", async () => {
    for (const key of ["boost", "predicate", "order"] as const) {
      const config = resolveConfig(
        {
          database: {
            vectorSearch: {
              "public.docs": { column: "embedding", [key]: "t.a >" },
            },
          },
        },
        "/project",
      );

      expect(await bad(config)).toContain(
        `vectorSearch.public.docs.${key} is not valid SQL`,
      );
    }
  });

  it("names the persona and fixture role setup that is not SQL", async () => {
    expect(
      await bad(
        withAuth({
          personas: [
            { name: "owner", setup: "insert into (", permissions: [] },
          ],
        }),
      ),
    ).toContain("authorization.personas[0].setup is not valid SQL");
    expect(
      await bad(
        withAuth({
          personas: "roles",
          fixtureRoles: [
            { name: "owner", setup: "insert into (", permissions: [] },
          ],
        }),
      ),
    ).toContain("authorization.fixtureRoles[0].setup is not valid SQL");
  });

  it("accepts setup statements with placeholders", async () => {
    await expect(
      checkConfigSql(
        withAuth({
          personas: [
            {
              name: "owner",
              setup:
                "insert into members (user_id, tenant_id) values ({user}, {tenant})",
              permissions: [],
            },
          ],
        }),
      ),
    ).resolves.toBeUndefined();
  });

  it("names the config key of a bad realtime trigger payload expression", async () => {
    const config = resolveConfig(
      {
        database: {
          realtime: {
            triggers: [
              {
                topic: "org:{org_id}",
                table: "orders",
                payload: { total: { sql: "{row}.a +" } },
              },
            ],
          },
        },
      },
      "/project",
    );

    expect(await bad(config)).toContain(
      "realtime.triggers[0].payload.total.sql is not valid SQL",
    );
  });
});
