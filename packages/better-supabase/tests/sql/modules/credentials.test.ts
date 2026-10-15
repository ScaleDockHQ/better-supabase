import { describe, expect, it } from "vitest";

import type { BlocksConfig } from "../../../src/config/blocks.ts";

import { tenantRefGuard } from "../../../src/sql/modules/credentials.ts";
import { moduleBody } from "../../../src/sql/render.ts";

const body = (modules: BlocksConfig = {}) =>
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

  it("guards refs to the row's tenant for every caller but the service role", () => {
    const guard = tenantRefGuard("r", "t");
    expect(guard).toContain(
      "jsonb_typeof(r -> 'tenant') is distinct from 'string'",
    );
    expect(guard).toContain("(r ->> 'tenant') is distinct from (t)::text");
    expect(guard).toContain("hint = 'CREDENTIAL_REF_FOREIGN'");
    expect(guard).toMatch(/^if not \(/);
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

  describe("adopt mode", () => {
    const adopted = (
      columns: Record<string, string | null> = {},
      options: Record<string, unknown> = {},
    ) =>
      body({
        credentials: {
          mode: "adopt",
          tables: { secrets: "public.integration_secrets" },
          columns: {
            secrets: { tenant: "organization_id", scope: null, ...columns },
          },
          options,
        },
      });

    it("reads the app's table through each row's Vault secret", () => {
      const sql = adopted();
      expect(sql).toContain(
        'join vault.decrypted_secrets ds on ds.id = s."vault_id"',
      );
      expect(sql).toContain(
        `s."provider"::text = v_provider and s."name"::text = v_name and s."organization_id"::text is not distinct from v_tenant`,
      );
      expect(sql).toContain("v_tenant := split_part(v_name, '/', 2);");
      expect(sql).not.toContain("v_scope := substring");
      expect(sql).toContain(
        "if v_provider = 'vault' and position(':' in v_name) > 1 then",
      );
      expect(sql).toContain(
        `insert into "public"."integration_secrets" ("provider", "name", "organization_id", "vault_id", "updated_at")`,
      );
      expect(sql).toContain(
        'jsonb_populate_record(null::"public"."integration_secrets"',
      );
      expect(sql).toContain(
        `create trigger "bs_credential_vault" after delete or update of "vault_id" on "public"."integration_secrets"`,
      );
      expect(sql.match(/security definer/g)).toHaveLength(4);
    });

    it("keeps the secret in a column with secretStorage column", () => {
      const sql = adopted(
        { vaultId: null, updatedAt: null, scope: "user_id" },
        { secretStorage: "column" },
      );
      expect(sql).toContain(
        'select s."secret" from "public"."integration_secrets" s',
      );
      expect(sql).toContain("v_scope := substring(v_name from '@([^@/]+)$');");
      expect(sql).not.toContain("vault.create_secret");
      expect(sql).not.toContain('"updated_at"');
      expect(sql).toContain(
        'drop trigger if exists "bs_credential_vault" on "public"."integration_secrets";',
      );
    });

    it("refuses a storage the table has no column for, and renames in managed mode", () => {
      expect(() => adopted({ vaultId: null })).toThrow(
        /needs the secrets table's vaultId/,
      );
      expect(() => adopted({}, { secretStorage: "env" })).toThrow(
        /"vault" or "column"/,
      );
      expect(() =>
        body({ credentials: { columns: { secrets: { tenant: "org_id" } } } }),
      ).toThrow(/mode "adopt"/);
    });
  });

  it("is empty in custom mode", () => {
    expect(
      moduleBody("credentials", {
        modules: { credentials: { mode: "custom" } },
      }),
    ).toBeUndefined();
  });
});
