import { Pool } from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { defineSupabase } from '../core/define.ts';
import { mapDbError, type RawDbError } from '../core/errors.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { createIdempotency, createInbox, createJobs } from '../jobs/index.ts';
import { createPostgres } from '../postgres/pool.ts';
import { renderKit, SQL_MODULES } from '../sql/kit.ts';
import { asUser } from '../testing/as-user.ts';
import { signWebhook } from '../webhooks/index.ts';

const url = process.env['SUPABASE_URL'] ?? 'http://127.0.0.1:55421';
const dbUrl =
  process.env['SUPABASE_DB_URL'] ??
  'postgresql://postgres:postgres@127.0.0.1:55422/postgres';
const publishableKey =
  process.env['SUPABASE_PUBLISHABLE_KEY'] ??
  'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

const ACME = '00000000-0000-4000-8000-000000000001';
const RUN = String(Date.now());

async function reachable(): Promise<boolean> {
  const pool = new Pool({
    connectionString: dbUrl,
    max: 1,
    connectionTimeoutMillis: 1000,
  });
  try {
    await pool.query('select 1');
    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const live = await reachable();

describe.skipIf(!live)('SQL kit against the local database', () => {
  const pool = new Pool({ connectionString: dbUrl, max: 4 });
  const postgres = createPostgres({ connectionString: dbUrl, max: 4 });
  const table = `public.bs_kit_${RUN}`;

  beforeAll(async () => {
    for (const module of Object.values(SQL_MODULES)) {
      if (module.target === 'schema') await pool.query(module.sql);
    }
    await pool.query(`
      create table ${table} (
        id uuid primary key default gen_random_uuid(),
        organization_id uuid,
        slug text,
        name text,
        created_by uuid,
        updated_by uuid,
        updated_at timestamptz
      );
      grant all on ${table} to authenticated;
      select better_supabase.track_updated_at('${table}');
      select better_supabase.track_actor('${table}');
      select better_supabase.track_slug('${table}');
      select better_supabase.audit('${table}', ignore => '{updated_at}');
    `);
  });
  afterAll(async () => {
    await pool.query(`drop table if exists ${table}`);
    await pool.query(
      `delete from better_supabase.audited_tables where target::text = $1`,
      [table.replace('public.', '')],
    );
    await pool.query(
      `select pgmq.drop_queue(queue_name) from pgmq.list_queues() where queue_name like $1`,
      [`kit_${RUN}%`],
    );
    await pool.query(
      `delete from better_supabase.webhook_inbox where source = $1`,
      [`kit-${RUN}`],
    );
    await pool.query(
      `delete from better_supabase.idempotency_keys where scope = $1`,
      [RUN],
    );
    await pool.end();
    await postgres.end();
  });

  it('is idempotent', async () => {
    for (const module of Object.values(SQL_MODULES)) {
      if (module.target === 'schema') await pool.query(module.sql);
    }
  });

  it('grants tables in expose to the Data API roles', async () => {
    const name = `bs_grants_${RUN}`;
    const read = async (): Promise<Response> => {
      for (let attempt = 0; ; attempt++) {
        const response = await fetch(`${url}/rest/v1/${name}?select=id`, {
          headers: { apikey: publishableKey },
        });
        const body = (await response.clone().json()) as { code?: string };
        if (body.code !== 'PGRST205' || attempt === 20) return response;
        await new Promise((done) => setTimeout(done, 250));
      }
    };
    try {
      await pool.query(`
        create table public.${name} (id int primary key);
        alter table public.${name} enable row level security;
        create policy "read" on public.${name} for select using (true);
        revoke all on public.${name} from anon, authenticated;
        notify pgrst, 'reload schema';
      `);
      const denied = await read();
      const raw = (await denied.json()) as RawDbError;
      expect(raw.code).toBe('42501');
      expect(mapDbError(raw)).toMatchObject({
        kind: 'forbidden',
        hint: expect.stringContaining('expose'),
      });

      const [file] = renderKit(['grants'], {
        grants: [{ table: name, role: 'anon', privileges: ['select'] }],
      });
      await pool.query(file!.contents);
      const allowed = await read();
      expect(allowed.status).toBe(200);
      expect(await allowed.json()).toEqual([]);
    } finally {
      await pool.query(`drop table if exists public.${name}`);
    }
  });

  it('stamps updated_at and actors, enforces slugs and audits changes', async () => {
    const user = crypto.randomUUID();
    const claims = { sub: user, role: 'authenticated' };
    const as = postgres.asUser(claims);
    const [row] = await as.queryRaw<{
      id: string;
      created_by: string;
      updated_by: string;
    }>(
      `insert into ${table} (organization_id, slug, name) values ($1, 'acme', 'Acme') returning *`,
      [ACME],
    );
    expect(row).toMatchObject({ created_by: user, updated_by: user });

    const [updated] = await as.queryRaw<{ updated_at: Date | null }>(
      `update ${table} set name = 'Acme 2' where id = $1 returning updated_at`,
      [row!.id],
    );
    expect(updated!.updated_at).toBeInstanceOf(Date);

    await expect(
      as.queryRaw(`insert into ${table} (slug) values ('admin')`),
    ).rejects.toMatchObject({ code: '23514', hint: 'SLUG_RESERVED' });
    await expect(
      as.queryRaw(`insert into ${table} (slug) values ('Bad Slug')`),
    ).rejects.toMatchObject({ hint: 'SLUG_INVALID' });

    const log = await pool.query<{
      op: string;
      changed: string[] | null;
      actor_id: string;
      org_id: string;
    }>(
      `select op, changed, actor_id, org_id from better_supabase.audit_log
       where table_name = $1 and record_id = $2 order by id`,
      [table, row!.id],
    );
    expect(log.rows).toEqual([
      { op: 'insert', changed: null, actor_id: user, org_id: ACME },
      { op: 'update', changed: ['name'], actor_id: user, org_id: ACME },
    ]);
    await expect(
      as.queryRaw('select * from better_supabase.audit_log limit 1'),
    ).rejects.toMatchObject({ code: '42501' });
  });

  it('runs invitations through memberships and has_org_role', async () => {
    const owner = await pool.query<{ id: string }>(
      `insert into auth.users (id, instance_id, aud, role, email) values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', $1) returning id`,
      [`owner-${RUN}@example.com`],
    );
    const invitee = await pool.query<{ id: string }>(
      `insert into auth.users (id, instance_id, aud, role, email) values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', $1) returning id`,
      [`invitee-${RUN}@example.com`],
    );
    const org = crypto.randomUUID();
    const ownerId = owner.rows[0]!.id;
    const inviteeId = invitee.rows[0]!.id;
    try {
      await pool.query(
        `insert into better_supabase.memberships (org_id, user_id, role) values ($1, $2, 'owner')`,
        [org, ownerId],
      );
      const asOwner = postgres.asUser({
        sub: ownerId,
        email: `owner-${RUN}@example.com`,
      });
      const asInvitee = postgres.asUser({
        sub: inviteeId,
        email: `invitee-${RUN}@example.com`,
      });

      await expect(
        asInvitee.queryRaw('select better_supabase.create_invitation($1, $2)', [
          org,
          'x@example.com',
        ]),
      ).rejects.toMatchObject({ code: '42501' });
      const [{ token }] = (await asOwner.queryRaw<{ token: string }>(
        `select better_supabase.create_invitation($1, $2, 'admin') as token`,
        [org, `invitee-${RUN}@example.com`],
      )) as [{ token: string }];

      const [accepted] = await asInvitee.queryRaw<{ org: string }>(
        'select better_supabase.accept_invitation($1) as org',
        [token],
      );
      expect(accepted!.org).toBe(org);
      const [role] = await asInvitee.queryRaw<{ admin: boolean }>(
        `select better_supabase.has_org_role($1, '{admin}') as admin`,
        [org],
      );
      expect(role!.admin).toBe(true);
      await expect(
        asInvitee.queryRaw('select better_supabase.accept_invitation($1)', [
          token,
        ]),
      ).rejects.toMatchObject({ hint: 'INVITATION_INVALID' });
    } finally {
      await pool.query(
        'delete from better_supabase.memberships where org_id = $1',
        [org],
      );
      await pool.query(
        'delete from better_supabase.invitations where org_id = $1',
        [org],
      );
      await pool.query('delete from auth.users where id = any($1)', [
        [ownerId, inviteeId],
      ]);
    }
  });

  it('queues, retries, dedupes and dead-letters jobs on pgmq', async () => {
    const queue = `kit_${RUN}`;
    const jobs = createJobs(postgres.admin, {
      [queue]: z.object({ to: z.email() }),
    });
    const invalid = await jobs.enqueue(queue, { to: 'nope' });
    expect(invalid).toMatchObject({ ok: false, error: { kind: 'validation' } });

    const first = await jobs
      .enqueue(queue, { to: 'a@example.com' }, { dedupeKey: 'a' })
      .orThrow();
    const again = await jobs
      .enqueue(queue, { to: 'a@example.com' }, { dedupeKey: 'a' })
      .orThrow();
    expect(again).toBe(first);
    await jobs
      .enqueue(queue, { to: 'b@example.com' }, { maxAttempts: 1 })
      .orThrow();
    await jobs
      .enqueue(queue, { to: 'later@example.com' }, { delay: 3600 })
      .orThrow();

    const other = createJobs(postgres.admin, {
      [queue]: z.object({ to: z.email() }),
    });
    const [mine, theirs] = await Promise.all([
      jobs.claim(queue, { batch: 1 }).orThrow(),
      other.claim(queue, { batch: 1 }).orThrow(),
    ]);
    expect(mine).toHaveLength(1);
    expect(theirs).toHaveLength(1);
    expect(mine[0]!.id).not.toBe(theirs[0]!.id);
    expect(await jobs.complete({ ...mine[0]!, attempts: 99 }).orThrow()).toBe(
      false,
    );
    expect(
      await jobs.fail(mine[0]!, new Error('boom'), { retryIn: 0 }).orThrow(),
    ).toMatch(/queued|dead/);
    expect(
      await other.fail(theirs[0]!, 'boom', { retryIn: 0 }).orThrow(),
    ).toMatch(/queued|dead/);

    const seen: string[] = [];
    const drained = await jobs.drain(queue, (payload, job) => {
      seen.push(payload.to);
      if (job.attempts < 3 && payload.to === 'a@example.com')
        throw new Error('retry me');
      return undefined;
    });
    expect(drained.succeeded + drained.failed).toBeGreaterThan(0);
    const waiting = await pool.query<{
      message: { payload: { to: string }; last_error?: string };
      read_ct: number;
    }>(`select message, read_ct from pgmq.q_${queue} order by msg_id`);
    const archived = await pool.query<{
      message: { payload: { to: string }; dead?: boolean };
      read_ct: number;
    }>(`select message, read_ct from pgmq.a_${queue} order by msg_id`);
    const waitingBy = new Map(
      waiting.rows.map((row) => [row.message.payload.to, row]),
    );
    const archivedBy = new Map(
      archived.rows.map((row) => [row.message.payload.to, row]),
    );
    expect(archivedBy.get('b@example.com')).toMatchObject({
      read_ct: 1,
      message: { dead: true },
    });
    expect(waitingBy.get('later@example.com')).toMatchObject({ read_ct: 0 });
    expect(waitingBy.get('a@example.com')?.message.last_error).toBe('retry me');
  });

  it('schedules recurring jobs with pg_cron', async () => {
    const queue = `kit_${RUN}_cron`;
    const jobs = createJobs(postgres.admin, {
      [queue]: z.object({ kind: z.string() }),
    });
    const name = `bs-kit-${RUN}`;
    await pool.query(
      'create extension if not exists pg_cron with schema pg_catalog',
    );
    await jobs.schedule(name, '0 3 * * *', queue, { kind: 'digest' }).orThrow();
    const { rows } = await pool.query<{ command: string }>(
      'select command from cron.job where jobname = $1',
      [name],
    );
    expect(rows[0]?.command).toContain(`enqueue_job('${queue}'`);
    expect(await jobs.unschedule(name).orThrow()).toBe(true);
  });

  it('works a queue until the signal aborts', async () => {
    const queue = `kit_${RUN}_work`;
    const jobs = createJobs(postgres.admin, {
      [queue]: z.object({ n: z.number() }),
    });
    for (const n of [1, 2, 3, 4]) await jobs.enqueue(queue, { n }).orThrow();
    const controller = new AbortController();
    const done: number[] = [];
    const result = await jobs.work(
      queue,
      (payload) => {
        done.push(payload.n);
        if (done.length === 4) controller.abort();
        return undefined;
      },
      { concurrency: 2, pollInterval: 20, signal: controller.signal },
    );
    expect(done.toSorted((a, b) => a - b)).toEqual([1, 2, 3, 4]);
    expect(result).toEqual({ succeeded: 4, failed: 0 });
  });

  it('replays idempotent requests and rejects reuse', async () => {
    const idempotency = createIdempotency(postgres.admin, { scope: RUN });
    let runs = 0;
    const handler = async () => {
      runs += 1;
      return Response.json({ order: runs }, { status: 201 });
    };
    const request = (body: string, key = 'order-1') =>
      new Request('https://api.test/orders', {
        method: 'POST',
        headers: { 'idempotency-key': key, 'content-type': 'application/json' },
        body,
      });
    const first = await idempotency.handle(request('{"sku":1}'), handler);
    expect(first.status).toBe(201);
    const replay = await idempotency.handle(request('{"sku":1}'), handler);
    expect(replay.status).toBe(201);
    expect(replay.headers.get('idempotency-replayed')).toBe('true');
    expect(await replay.json()).toEqual({ order: 1 });
    expect(runs).toBe(1);
    const reused = await idempotency.handle(request('{"sku":2}'), handler);
    expect(reused.status).toBe(422);

    const failing = await idempotency.handle(
      request('{}', 'order-2'),
      () => new Response('down', { status: 503 }),
    );
    expect(failing.status).toBe(503);
    expect(
      (await idempotency.handle(request('{}', 'order-2'), handler)).status,
    ).toBe(201);
  });

  it('stores verified webhooks once and processes them with retries', async () => {
    const secret = `whsec_${btoa('a-webhook-secret-for-the-inbox-test')}`;
    const inbox = createInbox(postgres.admin, {
      source: `kit-${RUN}`,
      secrets: secret,
    });
    const deliver = async (id: string, payload: unknown) => {
      const body = JSON.stringify(payload);
      const headers = await signWebhook(secret, { id, body });
      return inbox.receive(
        new Request('https://api.test/hooks', {
          method: 'POST',
          headers,
          body,
        }),
      );
    };
    expect(
      (await deliver('msg_1', { type: 'invoice.paid', n: 1 })).status,
    ).toBe(202);
    expect(
      (await deliver('msg_1', { type: 'invoice.paid', n: 1 })).status,
    ).toBe(200);
    expect(
      (await deliver('msg_2', { type: 'invoice.failed', n: 2 })).status,
    ).toBe(202);
    const forged = await inbox.receive(
      new Request('https://api.test/hooks', {
        method: 'POST',
        headers: {
          'webhook-id': 'x',
          'webhook-timestamp': '1',
          'webhook-signature': 'v1,AAAA',
        },
        body: '{}',
      }),
    );
    expect(forged.status).toBe(401);

    const types: string[] = [];
    const result = await inbox.process((message) => {
      types.push(message.type ?? '');
      if (message.type === 'invoice.failed') throw new Error('try later');
      return undefined;
    });
    expect(result).toEqual({ succeeded: 1, failed: 1 });
    expect(types.sort()).toEqual(['invoice.failed', 'invoice.paid']);
    expect(await inbox.process(() => undefined)).toEqual({
      succeeded: 0,
      failed: 0,
    });
  });

  it('pgTAP helpers authenticate as a user under RLS', async () => {
    const client = await pool.connect();
    try {
      await client.query('begin');
      const installed = await client.query<{ pass: string }>(
        SQL_MODULES['pgtap']!.sql,
      );
      expect(JSON.stringify(installed)).toContain('ok 1');
      const user = await client.query<{ id: string }>(
        `select tests.create_user($1) as id`,
        [`pgtap-${RUN}@example.com`],
      );
      await client.query(`select tests.authenticate_as($1, $2)`, [
        user.rows[0]!.id,
        JSON.stringify({ org_id: ACME }),
      ]);
      const visible = await client.query<{ n: number }>(
        `select count(*)::int as n from public.customers where organization_id <> $1`,
        [ACME],
      );
      expect(visible.rows[0]!.n).toBe(0);
      await client.query('select tests.clear_authentication()');
      const rls = await client.query<{ result: string }>(
        `select tests.rls_enabled('public') as result`,
      );
      expect(rls.rows[0]!.result).toMatch(/^not ok/);
      expect(rls.rows[0]!.result).toContain(`bs_kit_${RUN}`);
      await client.query(`alter table ${table} enable row level security`);
      const fixed = await client.query<{ result: string }>(
        `select tests.rls_enabled('public') as result`,
      );
      expect(fixed.rows[0]!.result).toMatch(/^ok/);
    } finally {
      await client.query('rollback');
      client.release();
    }
  });

  it('asUser runs PostgREST and SQL as the same user', async () => {
    const sb = defineSupabase(schema);
    const alice = await asUser(
      sb,
      { sub: crypto.randomUUID(), org_id: ACME },
      { url, publishableKey, postgres },
    );
    const rest = await alice.db.customers.count().orThrow();
    const sql = await alice.sql!.customers.count().orThrow();
    expect(rest).toBe(sql);
    expect(rest).toBeGreaterThan(0);
    const stranger = await asUser(
      sb,
      { sub: crypto.randomUUID() },
      { url, publishableKey },
    );
    expect(await stranger.db.customers.count().orThrow()).toBe(0);
  });
});
