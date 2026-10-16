import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody } from "../../../src/sql/render.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("signing-keys", { modules })!;

describe("signing-keys module", () => {
  it("keeps every function for the service role", () => {
    const sql = body();
    for (const signature of [
      '"add_signing_key"(text, text, text, text, jsonb, text)',
      '"signing_key"(text, text)',
      '"note_signing_key_exp"(text, timestamptz)',
      '"retire_signing_key"(text)',
      '"signing_jwks"(text, text, interval)',
      '"delete_signing_keys"(text, text)',
      '"purge_signing_keys"(interval)',
    ]) {
      expect(sql).toContain(
        `revoke execute on function "better_supabase".${signature} from public, anon, authenticated;`,
      );
      expect(sql).toContain(
        `grant execute on function "better_supabase".${signature} to service_role;`,
      );
    }
    expect(sql.match(/hint = 'SIGNING_KEYS_FORBIDDEN'/g)).toHaveLength(7);
  });

  it("keeps the private key in Vault and deletes it with the row", () => {
    const sql = body();
    expect(sql).toContain("check (not (\"public_jwk\" ? 'd'))");
    expect(sql).toContain("vault.create_secret(");
    expect(sql).toContain(
      'delete from vault.secrets vs where vs.id = old."vault_secret_id";',
    );
    expect(sql).toContain(
      'create unique index if not exists signing_keys_active_idx on "better_supabase"."signing_keys" ("owner_type", "owner_id") where "state" = \'active\';',
    );
  });

  it("quotes the jwksGrace option as an interval literal", () => {
    const sql = body({
      "signing-keys": { options: { jwksGrace: "1 hour'; drop table x; --" } },
    });
    expect(sql).toContain(
      "coalesce(grace, '1 hour''; drop table x; --'::interval)",
    );
  });
});
