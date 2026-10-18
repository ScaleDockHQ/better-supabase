import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/render.ts";

const body = () => moduleBody("oauth-server", {})!;

const SERVICE_FUNCTIONS = [
  '"register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid)',
  '"oauth_client"(text)',
  '"verify_oauth_client"(text, text)',
  '"verify_oauth_registration_token"(text, text)',
  '"update_oauth_client"(text, text, text[], text[], text, jsonb)',
  '"rotate_oauth_client_secret"(text, text)',
  '"delete_oauth_client"(text)',
  '"create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text)',
  '"redeem_oauth_authorization_code"(text, text, text, text)',
  '"create_oauth_device_code"(text, text, text, text, interval, integer)',
  '"oauth_device_request"(text)',
  '"decide_oauth_device_code"(text, uuid, boolean)',
  '"poll_oauth_device_code"(text, text)',
  '"list_oauth_grants"(uuid, boolean)',
  '"revoke_oauth_grant"(uuid)',
  '"revoke_oauth_token"(text, timestamptz, uuid)',
  '"is_oauth_token_revoked"(text, text)',
  '"purge_oauth_server"()',
];

describe("oauth-server module", () => {
  it("keeps the protocol functions for the service role", () => {
    const sql = body();

    for (const signature of SERVICE_FUNCTIONS) {
      expect(sql).toContain(
        `revoke execute on function "better_supabase".${signature} from public, anon, authenticated;`,
      );
      expect(sql).toContain(
        `grant execute on function "better_supabase".${signature} to service_role;`,
      );
    }

    // Every service function plus the internal grant helper.
    expect(sql.match(/hint = 'OAUTH_SERVER_FORBIDDEN'/g)).toHaveLength(
      SERVICE_FUNCTIONS.length + 1,
    );
    expect(sql).toContain(
      'revoke execute on function "better_supabase"."oauth_grant_for"(uuid, text, text[]) from public, anon, authenticated, service_role;',
    );
  });

  it("lets a signed-in user list and revoke only their own grants", () => {
    const sql = body();

    for (const signature of [
      '"my_oauth_grants"()',
      '"revoke_my_oauth_grant"(uuid)',
    ]) {
      expect(sql).toContain(
        `grant execute on function "better_supabase".${signature} to authenticated`,
      );
    }

    expect(sql).toContain('and g."user_id" = (select auth.uid())');
  });

  it("stores only hashes and an S256 challenge", () => {
    const sql = body();

    expect(sql).toContain(
      `"secret_hash" text check ("secret_hash" ~ '^[0-9a-f]{64}$')`,
    );
    expect(sql).toContain(
      `"code_hash" text primary key check ("code_hash" ~ '^[0-9a-f]{64}$')`,
    );
    expect(sql).toContain(
      `"code_challenge" text not null check ("code_challenge" ~ '^[A-Za-z0-9_-]{43}$')`,
    );
    expect(sql).toContain(
      `check (("token_endpoint_auth_method" = 'none') = ("secret_hash" is null))`,
    );
  });

  it("revokes the grant when a code is redeemed twice", () => {
    const sql = body();

    const redeem = sql.slice(
      sql.indexOf(
        'function "better_supabase"."redeem_oauth_authorization_code"',
      ),
    );

    expect(redeem).toContain('if v_code."consumed_at" is not null then');
    expect(redeem).toContain("'replayed', true");
  });

  it("counts an unknown grant as revoked", () => {
    const sql = body();

    const check = sql.slice(
      sql.indexOf('function "better_supabase"."is_oauth_token_revoked"'),
    );

    expect(check).toContain("return not exists (");
  });
});
