import { Pool, type PoolClient } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { renderKit } from "../../src/sql/kit.ts";
import { avatarBucket, orgLogoBucket } from "../../src/storage/index.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

async function reachable(): Promise<boolean> {
  const pool = new Pool({
    connectionString: dbUrl,
    max: 1,
    connectionTimeoutMillis: 1000,
  });
  try {
    await pool.query("select 1");
    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const live = await reachable();

const USERS = {
  ada: crypto.randomUUID(),
  bob: crypto.randomUUID(),
  eve: crypto.randomUUID(),
} as const;
type Who = keyof typeof USERS;
const SCHEMA = `bs_profiles_${USERS.ada.slice(0, 8)}`;
const PROFILES = `${SCHEMA}.profiles`;

/** Runs `sql` as `who` through the authenticated role, inside a savepoint. */
async function as<T = Record<string, unknown>>(
  client: PoolClient,
  who: Who,
  sql: string,
  params: unknown[] = [],
): Promise<{ rows: T[]; error?: { code?: string; hint?: string } }> {
  await client.query("savepoint attempt");
  try {
    await client.query(
      "select set_config('request.jwt.claims', $1, true), set_config('role', 'authenticated', true)",
      [JSON.stringify({ sub: USERS[who], role: "authenticated" })],
    );
    const { rows } = await client.query(sql, params);
    await client.query("reset role");
    await client.query("release savepoint attempt");
    // SAFETY: the caller names the row shape of its own query.
    return { rows: rows as T[] };
  } catch (error) {
    await client.query("rollback to savepoint attempt");
    return { rows: [], error: error as { code?: string; hint?: string } };
  }
}

describe.skipIf(!live)("profiles", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("creates, mirrors and guards profiles", async () => {
    const client = await pool.connect();
    try {
      await client.query("begin");
      const layout = {
        kits: {
          tenant: { schema: SCHEMA },
          access: { schema: SCHEMA },
          profiles: {
            schema: SCHEMA,
            options: { readPolicy: "members" },
            hooks: { schema: SCHEMA },
          },
        },
      };
      for (const file of renderKit(["tenant", "access", "profiles"], layout))
        await client.query(file.contents);

      const meta = {
        ada: { full_name: "Ada King Lovelace", user_name: "ada" },
        bob: { full_name: "Bob", user_name: "Ada" },
        eve: { given_name: "Eve", family_name: "Online" },
      };
      for (const who of Object.keys(USERS) as Who[]) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, raw_user_meta_data)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', $3)`,
          [USERS[who], `${who}-${USERS[who]}@example.test`, meta[who]],
        );
      }
      const profile = async (who: Who) =>
        (
          await client.query(`select * from ${PROFILES} where id = $1`, [
            USERS[who],
          ])
        ).rows[0] as Record<string, unknown> | undefined;

      expect(await profile("ada")).toMatchObject({
        username: "ada",
        first_name: "Ada",
        last_name: "King Lovelace",
        email: `ada-${USERS.ada}@example.test`,
      });
      expect((await profile("bob"))?.["username"]).toBe("ada1");
      expect(await profile("eve")).toMatchObject({
        full_name: "Eve Online",
        username: `eve${USERS.eve.replaceAll("-", "")}`.slice(0, 28),
      });

      await client.query("update auth.users set email = $2 where id = $1", [
        USERS.ada,
        "ada@new.test",
      ]);
      expect((await profile("ada"))?.["email"]).toBe("ada@new.test");

      const renamed = await as(
        client,
        "ada",
        `update ${PROFILES} set full_name = 'Ada L' where id = $1 returning full_name`,
        [USERS.ada],
      );
      expect(renamed.rows).toEqual([{ full_name: "Ada L" }]);
      const email = await as(
        client,
        "ada",
        `update ${PROFILES} set email = 'x@y.z' where id = $1`,
        [USERS.ada],
      );
      expect(email.error?.code).toBe("42501");
      const other = await as(
        client,
        "ada",
        `update ${PROFILES} set full_name = 'Mallory' where id = $1 returning id`,
        [USERS.bob],
      );
      expect(other.rows).toEqual([]);

      const visible = async (who: Who) =>
        (
          await as<{ id: string }>(
            client,
            who,
            `select id from ${PROFILES} order by id`,
          )
        ).rows.map((row) => row.id);
      expect(await visible("ada")).toEqual([USERS.ada]);
      const org = crypto.randomUUID();
      await client.query(
        `insert into ${SCHEMA}.memberships (org_id, user_id, role) values ($1, $2, 'owner'), ($1, $3, 'member')`,
        [org, USERS.ada, USERS.bob],
      );
      expect(await visible("ada")).toEqual([USERS.ada, USERS.bob].toSorted());
      expect(await visible("eve")).toEqual([USERS.eve]);
      const peerEmail = await as(
        client,
        "ada",
        `select email from ${PROFILES} where id = $1`,
        [USERS.bob],
      );
      expect(peerEmail.error?.code).toBe("42501");
      const own = await as<{ email: string }>(
        client,
        "ada",
        `select email from ${SCHEMA}.my_profile()`,
      );
      expect(own.rows).toEqual([{ email: "ada@new.test" }]);

      const removed = await client.query(
        `delete from ${PROFILES} where id = $1 returning id`,
        [USERS.eve],
      );
      expect(removed.rowCount).toBe(1);
      const backfilled = await client.query(
        `select ${SCHEMA}.backfill_profiles() as n`,
      );
      expect(backfilled.rows[0].n).toBeGreaterThanOrEqual(1);
      expect(await profile("eve")).toBeDefined();

      // Usernames follow the length, character and reserved-name rules.
      for (const name of ["admin", "x", "1abc", "ada king"]) {
        const bad = await as(
          client,
          "ada",
          `update ${PROFILES} set username = $2 where id = $1`,
          [USERS.ada, name],
        );
        expect(bad.error?.code).toBe("23514");
      }

      // A reserved name gets a suffix, and a failing after_profile_sync
      // hook leaves the user signed up without a profile.
      await client.query(`
        create function ${SCHEMA}.after_profile_sync(user_id uuid) returns void
        language plpgsql set search_path = '' as $$
        begin
          if exists (select 1 from auth.users u where u.id = user_id and u.email like 'broken-%') then
            raise exception 'CRM is down';
          end if;
        end;
        $$;`);
      const [admin, broken] = [crypto.randomUUID(), crypto.randomUUID()];
      await client.query(
        `insert into auth.users (id, email, aud, role, instance_id, raw_user_meta_data)
         values ($1, $3, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', '{"user_name": "admin"}'),
                ($2, $4, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', '{}')`,
        [
          admin,
          broken,
          `admin-${admin}@example.test`,
          `broken-${broken}@example.test`,
        ],
      );
      const usernames = await client.query(
        `select id, username from ${PROFILES} where id = any($1)`,
        [[admin, broken]],
      );
      expect(usernames.rows).toEqual([
        { id: admin, username: expect.stringMatching(/^admin\d+$/) },
      ]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("lets org logos follow the access contract", async () => {
    const client = await pool.connect();
    try {
      await client.query("begin");
      for (const file of renderKit(["tenant", "access"], {}))
        await client.query(file.contents);
      for (const who of ["ada", "bob"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')`,
          [USERS[who], `${who}-${USERS[who]}@example.test`],
        );
      }
      const org = crypto.randomUUID();
      await client.query(
        "insert into better_supabase.organizations (id, name, slug) values ($1::uuid, 'Test', 'test-' || left($1::text, 8)) on conflict do nothing",
        [org],
      );
      await client.query(
        "insert into better_supabase.memberships (org_id, user_id, role) values ($1, $2, 'owner'), ($1, $3, 'member')",
        [org, USERS.ada, USERS.bob],
      );
      const logos = orgLogoBucket({ id: `logos-${org.slice(0, 8)}` });
      const avatars = avatarBucket({ id: `avatars-${org.slice(0, 8)}` });
      await client.query(logos.sql());
      await client.query(avatars.sql());

      const upload = (who: Who, bucket: string, name: string) =>
        as(
          client,
          who,
          "insert into storage.objects (bucket_id, name, owner_id) values ($1, $2, $3) returning name",
          [bucket, name, USERS[who]],
        );
      const logo = logos.path({ orgId: org, version: "v1", ext: "png" });
      expect((await upload("ada", logos.id, logo)).rows).toHaveLength(1);
      expect((await upload("bob", logos.id, logo)).error?.code).toBe("42501");
      const avatar = (who: Who) =>
        avatars.path({ userId: USERS[who], version: "v1", ext: "png" });
      expect(
        (await upload("bob", avatars.id, avatar("bob"))).rows,
      ).toHaveLength(1);
      expect((await upload("bob", avatars.id, avatar("ada"))).error?.code).toBe(
        "42501",
      );
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
