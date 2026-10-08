import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/registry.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const render = (
  options: Record<string, unknown>,
  permissionCatalog?: readonly string[],
) =>
  moduleBody("api-keys", {
    modules: { "api-keys": { options } },
    ...(permissionCatalog ? { permissionCatalog } : {}),
  })!;

describe("api-keys module", () => {
  it("limits scopes to the provider's permissions", () => {
    const sql = render({ scopes: "catalog" }, [
      "invoice.read",
      "apiKey.manage",
    ]);
    expect(sql).toContain(`'{invoice.read,apiKey.manage}'::text[]`);
    expect(() => render({ scopes: "catalog" })).toThrow(
      /no authorization.permissions to read/,
    );
    expect(render({ scopes: ["deal.read", "deals:write"] })).toContain(
      `'{deal.read,deals:write}'::text[]`,
    );
    expect(() => render({ scopes: ["bad scope"] })).toThrow(/is not a scope/);
  });

  it("refuses the * scope under the provider model", () => {
    const sql = moduleBody("api-keys", {
      modules: { access: { model: "provider" } },
      accessProvider: moduleProvider,
    })!;
    expect(sql).toContain("API_KEY_SCOPE_WILDCARD");
    expect(render({})).not.toContain("API_KEY_SCOPE_WILDCARD");
  });

  it("returns each key's state and successor by the database clock", () => {
    const sql = render({});
    expect(sql).toContain(
      `when k."revoked_at" is not null and k."revoked_at" <= now() then 'revoked'`,
    );
    expect(sql).toContain(
      `when k."expires_at" is not null and k."expires_at" <= now() then 'expired'`,
    );
    expect(sql).toContain(`when k."revoked_at" is not null then 'grace'`);
    expect(sql).toContain(
      `'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = k."id" order by s."created_at" desc limit 1)`,
    );
    const verify = sql.slice(sql.indexOf("verify_api_key(public_id text"));
    expect(verify.slice(0, verify.indexOf("$$;"))).not.toContain(
      "successor_id",
    );
  });

  it("defaults the token prefix from options.prefix", () => {
    expect(render({})).toContain("prefix text default 'bs'");
    expect(render({ prefix: "pdk" })).toContain("prefix text default 'pdk'");
    expect(() => render({ prefix: "Bad" })).toThrow(/lowercase/);
  });
});
