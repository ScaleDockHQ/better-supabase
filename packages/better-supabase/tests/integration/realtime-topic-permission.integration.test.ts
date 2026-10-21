import { Pool } from "pg";
import { afterAll, afterEach, beforeEach, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import { defineTopic } from "../../src/realtime/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const RUN = String(Date.now());
const SCHEMA = `bs_perm_${RUN}`;

// A stand-in provider: `permitted` answers from a grants table per instance.
const PROVIDER = `
create schema ${SCHEMA};
grant usage on schema ${SCHEMA} to authenticated;
create table ${SCHEMA}.grants (user_id uuid, permission text, resource text, instance text, tenant text);
create function ${SCHEMA}.permitted(permission text, resource text, instance text, tenant text, scope text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from ${SCHEMA}.grants g
    where g.user_id = auth.uid() and g.permission = permitted.permission
      and g.resource = permitted.resource and g.instance = permitted.instance
      and g.tenant is not distinct from permitted.tenant and scope = 'tenant'
  )
$$;
grant execute on function ${SCHEMA}.permitted(text, text, text, text, text) to authenticated;
`;

describe.skipIf(!live)("realtime topic permission", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  let s: BlockSession;
  let holder: TestUser;
  let peer: TestUser;
  let tenant: string;
  beforeEach(async () => {
    s = await BlockSession.open(pool);
    await s.install(["organizations"]);
    holder = await s.user("holder");
    peer = await s.user("peer");
    // The organizations module gives admins `audit.read` and members not.
    tenant = await s.organization(await s.user("owner"), {
      admin: holder,
      member: peer,
    });
  });
  afterEach(() => s.close());

  afterAll(() => pool.end());

  /**
   * Sends one broadcast as postgres, then counts what `user` can select on
   * `topic`.
   */
  const visible = async (topic: string, user: TestUser): Promise<number> => {
    await s.client.query("reset role");
    await s.client.query(
      "select realtime.send(jsonb_build_object('n', 1), 'changed', $1, true)",
      [topic],
    );
    await s.asRole(user, { tenant_id: tenant });
    await s.client.query("select set_config('realtime.topic', $1, true)", [
      topic,
    ]);

    const count = await s.value<string>(
      "(select count(*) from realtime.messages where topic = $1)",
      [topic],
    );

    await s.client.query("reset role");

    return Number(count);
  };

  it("lets only the member holding the permission read the topic through the access contract", async () => {
    const audits = defineTopic(
      `perm_${RUN}:{organizationId}:audits:{auditId}`,
      { permission: "audit.read" },
    );

    await s.client.query(audits.sql());
    const topic = audits.topic({ organizationId: tenant, auditId: "a1" });

    await s.client.query("reset role");
    expect(
      Number(
        await s.value<string>(
          "(select count(*) from realtime.messages where topic = $1)",
          [topic],
        ),
      ),
    ).toBe(0);
    expect(await visible(topic, holder)).toBe(1);
    expect(await visible(topic, peer)).toBe(0);
  });

  it("asks the provider's permitted template about the instance in the topic", async () => {
    await s.client.query(PROVIDER);
    await s.client.query(
      `insert into ${SCHEMA}.grants values ($1, 'posts.read', 'posts', 'p1', $2)`,
      [holder.id, tenant],
    );

    const posts = defineTopic(`perm_${RUN}:{organizationId}:posts:{postId}`, {
      permission: "posts.read",
    });

    await s.client.query(
      posts.sql({
        functions: {
          idsWith: `${SCHEMA}.ids_with({permission})`,
          isPlatform: `${SCHEMA}.is_platform({permission})`,
          permitted: `${SCHEMA}.permitted({permission}, {resource}, {id}, {tenant}, '{scope}')`,
        },
      }),
    );
    const p1 = posts.topic({ organizationId: tenant, postId: "p1" });
    const p2 = posts.topic({ organizationId: tenant, postId: "p2" });

    expect(await visible(p1, holder)).toBe(1);
    expect(await visible(p1, peer)).toBe(0);
    expect(await visible(p2, holder)).toBe(0);
  });
});
