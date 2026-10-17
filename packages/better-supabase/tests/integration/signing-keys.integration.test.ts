import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createSigningKeys,
  sqlTransport,
  verifyCompact,
} from "../../src/blocks/signing-keys/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const OWNER = { type: "organization", id: "org-signing" };

describe.skipIf(!live)("signing-keys module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("keeps the private key in Vault, rotates and publishes retired keys until their exp", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["signing-keys"]);
      await s.service();
      await s.client.query("set local role service_role");
      const keys = createSigningKeys({ transport: sqlTransport(s.sql) });

      const first = await keys.create(OWNER).orThrow();
      const exp = Math.floor(Date.now() / 1000) + 3600;

      const token = await keys
        .signer(OWNER)
        .signJwt({ sub: "u1", exp })
        .orThrow();

      const second = await keys.rotate(OWNER, "ES256").orThrow();
      expect(second).toMatchObject({ alg: "ES256", retired: first.kid });

      const jwks = await keys.jwks(OWNER).orThrow();
      expect(new Set(jwks.keys.map((key) => key.kid))).toEqual(
        new Set([first.kid, second.kid]),
      );
      expect(jwks.keys.every((key) => key.d === undefined)).toBe(true);
      expect((await verifyCompact(token, jwks)).payload).toMatchObject({
        sub: "u1",
      });
      expect(await keys.purge().orThrow()).toBe(0);

      await s.client.query("reset role");
      expect(
        await s.value<number>(
          "(select count(*)::int from vault.secrets where name like 'bs:signing:%' and name in ($1, $2))",
          [`bs:signing:${first.kid}`, `bs:signing:${second.kid}`],
        ),
      ).toBe(2);
      await s.client.query("set local role service_role");
      expect(await keys.remove(OWNER).orThrow()).toBe(2);
      await s.client.query("reset role");
      expect(
        await s.value<number>(
          "(select count(*)::int from vault.secrets where name in ($1, $2))",
          [`bs:signing:${first.kid}`, `bs:signing:${second.kid}`],
        ),
      ).toBe(0);
    } finally {
      await s.close();
    }
  });

  it("refuses callers other than the service role", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["signing-keys"]);
      const alice = await s.user("alice");
      await s.asRole(alice);
      expect(
        await s.hint(
          "select better_supabase.signing_jwks('organization', 'org-signing')",
        ),
      ).toMatch(/permission denied|SIGNING_KEYS_FORBIDDEN/);
    } finally {
      await s.close();
    }
  });
});
