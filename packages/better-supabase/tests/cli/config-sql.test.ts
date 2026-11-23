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
