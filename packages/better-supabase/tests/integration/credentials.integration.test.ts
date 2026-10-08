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
