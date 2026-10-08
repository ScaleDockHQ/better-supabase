import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody } from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) =>
  moduleBody("credentials", { modules })!;

describe("credentials module", () => {
  it("keeps every function for the service role", () => {
    const sql = body();
    for (const signature of [
      '"credential_get"(text, text)',
      '"credential_set"(text, text, text, text)',
      '"credential_delete"(text, text)',
    ]) {
      expect(sql).toContain(
        `revoke execute on function "better_supabase".${signature} from public, anon, authenticated;`,
      );
      expect(sql).toContain(
        `grant execute on function "better_supabase".${signature} to service_role;`,
      );
    }
    expect(sql.match(/security definer/g)).toHaveLength(3);
    expect(sql.match(/set search_path = ''/g)).toHaveLength(3);
  });

  it("names Vault secrets under bs:cred and checks the caller and the name", () => {
    const sql = body();
    expect(sql).toContain(
      "'bs:cred:' || credential_get.provider || ':' || credential_get.name",
    );
    expect(sql).toContain("hint = 'CREDENTIALS_FORBIDDEN'");
    expect(sql).toContain("hint = 'CREDENTIAL_NAME_INVALID'");
    expect(sql).toContain("vault.create_secret(");
    expect(sql).toContain("vault.update_secret(v_id, credential_set.secret)");
  });

  it("is empty in custom mode", () => {
    expect(
      moduleBody("credentials", {
        modules: { credentials: { mode: "custom" } },
      }),
    ).toBeUndefined();
  });
});
