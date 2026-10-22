import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { signWebhook } from "../../src/blocks/webhooks/verify.ts";
import { sqlTransport, vaultCredentials } from "../../src/credentials/index.ts";
import { testCredentialProvider } from "../../src/testing/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("credentials module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("passes the CredentialProvider kit over Vault", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["credentials"]);
      await s.service();
      const vault = vaultCredentials({ transport: sqlTransport(s.sql) });

      const report = await testCredentialProvider(vault, {
        ref: { provider: "vault", secret: `kit-${crypto.randomUUID()}` },
        userRef: {
          provider: "vault",
          secret: `kit-user-${crypto.randomUUID()}`,
          scope: "user",
        },
        inbound: {
          ref: {
            provider: "vault",
            secret: `kit-hooks-${crypto.randomUUID()}`,
            inbound: "standard-webhooks",
          },
          async sign(body, secret) {
            return new Request("https://app.test/hooks", {
              method: "POST",
              headers: await signWebhook(secret, { id: "msg_1", body }),
              body,
            });
          },
        },
        seed: (ref, subject, value) =>
          vault.set(ref, value, { subject }).orThrow(),
      });

      expect(report.checks.every((check) => check.ok)).toBe(true);
      expect(
        await s.rows(
          "select count(*)::int as n from vault.secrets where name like 'bs:cred:vault:kit-user-%'",
        ),
      ).toEqual([{ n: 2 }]);
    } finally {
      await s.close();
    }
  });

  it("passes the kit over an adopted table with Vault ids", async () => {
    const s = await BlockSession.open(pool);
    const tenant = crypto.randomUUID();
    const table = `public.bsb_secrets_${tenant.slice(0, 8)}`;

    try {
      await s.rows(`
        create table ${table} (
          id bigint generated always as identity primary key,
          provider text not null,
          name text not null,
          organization_id uuid,
          user_id uuid,
          vault_id uuid,
          updated_at timestamptz
        )`);
      await s.install(["credentials"], {
        modules: {
          credentials: {
            mode: "adopt",
            tables: { secrets: table },
            columns: {
              secrets: {
                tenant: "organization_id",
                scope: "user_id",
                secret: null,
              },
            },
          },
        },
      });
      await s.service();

      const vault = vaultCredentials({
        transport: sqlTransport(s.sql),
        cacheMs: 0,
      });

      const ref = { provider: "vault", secret: "openai:api-key", tenant };
      const app = { subject: { type: "app" as const } };

      const report = await testCredentialProvider(vault, {
        ref,
        userRef: { provider: "vault", secret: "github:token", scope: "user" },
        seed: (seedRef, subject, value) =>
          vault.set(seedRef, value, { subject }).orThrow(),
      });

      expect(report.checks.filter((check) => !check.ok)).toEqual([]);

      await vault.set(ref, "sk-2").orThrow();
      await vault.set(ref, "sk-3").orThrow();

      const rows = await s.rows<{
        provider: string;
        name: string;
        tenant: string;
        vault: boolean;
      }>(
        `select provider, name, organization_id::text as tenant, vault_id is not null as vault
         from ${table} where organization_id is not null`,
      );

      expect(rows).toEqual([
        { provider: "openai", name: "api-key", tenant, vault: true },
      ]);
      expect((await vault.getToken(ref, app).orThrow()).token).toBe("sk-3");

      const [row] = await s.rows<{ id: string }>(
        `select vault_id::text as id from ${table} where organization_id is not null`,
      );

      expect(await vault.revoke(ref, app).orThrow()).toBe(true);
      expect(
        await s.rows(
          "select count(*)::int as n from vault.secrets where id = $1",
          [row?.id],
        ),
      ).toEqual([{ n: 0 }]);
    } finally {
      await s.close();
    }
  });

  it("reads and writes an adopted secret column", async () => {
    const s = await BlockSession.open(pool);
    const table = `public.bsb_plain_${crypto.randomUUID().slice(0, 8)}`;

    try {
      await s.rows(
        `create table ${table} (provider text not null, name text not null, secret text not null, unique (provider, name))`,
      );
      await s.rows(
        `insert into ${table} values ('stripe', 'live', 'sk_live_1')`,
      );
      await s.install(["credentials"], {
        modules: {
          credentials: {
            mode: "adopt",
            tables: { secrets: table },
            columns: {
              secrets: {
                tenant: null,
                scope: null,
                vaultId: null,
                updatedAt: null,
              },
            },
            options: { secretStorage: "column" },
          },
        },
      });
      await s.service();
      expect(
        await s.rows(
          "select better_supabase.credential_get('stripe', 'live') as v",
        ),
      ).toEqual([{ v: "sk_live_1" }]);
      expect(
        await s.rows(
          "select better_supabase.credential_set('vault', 'stripe:live', 'sk_live_2') as id",
        ),
      ).toEqual([{ id: null }]);
      expect(await s.rows(`select secret from ${table}`)).toEqual([
        { secret: "sk_live_2" },
      ]);
      expect(
        await s.rows(
          "select better_supabase.credential_delete('stripe', 'live') as gone",
        ),
      ).toEqual([{ gone: true }]);
    } finally {
      await s.close();
    }
  });

  it("refuses users and bad names", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["credentials"]);
      const user = await s.user("reader");
      await s.service();
      await s.rows(
        "select better_supabase.credential_set('vault', 'private', 'xoxb-1')",
      );
      expect(
        await s.hint(
          "select better_supabase.credential_set('vault', 'bad name', 'x')",
        ),
      ).toBe("CREDENTIAL_NAME_INVALID");
      expect(
        await s.hint(
          "select better_supabase.credential_set('vault', 'empty', '')",
        ),
      ).toBe("CREDENTIAL_EMPTY");

      await s.as(user);
      expect(
        await s.hint(
          "select better_supabase.credential_get('vault', 'private')",
        ),
      ).toBe("CREDENTIALS_FORBIDDEN");
      await s.asRole(user);
      expect(
        await s.hint(
          "select better_supabase.credential_get('vault', 'private')",
        ),
      ).toMatch(/permission denied/);
    } finally {
      await s.close();
    }
  });
});
