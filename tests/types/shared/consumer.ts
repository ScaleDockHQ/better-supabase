import type { SupabaseClient } from '@supabase/supabase-js';

import { QueryClient } from '@tanstack/react-query';
import {
  type AsyncResult,
  type BetterResultShape,
  type CacheAdapter,
  type DbError,
  defineRepository,
  defineSupabase,
  type Executor,
  fromBetterResult,
  type Logger,
  memoryCache,
  ok,
  type Result,
  silentLogger,
  toBetterResult,
} from 'better-supabase';
import { createBrowser } from 'better-supabase/client';
import { defineConfig, zod } from 'better-supabase/config';
import { createEdge } from 'better-supabase/edge';
import { parseEnv } from 'better-supabase/env';
import { forwardMutations, httpSink } from 'better-supabase/events';
import { createHono } from 'better-supabase/hono';
import { defineListQuery } from 'better-supabase/list';
import {
  createNext,
  hasEntitlement,
  nextCache,
  requireAal,
} from 'better-supabase/next';
import { createImageLoader } from 'better-supabase/next/image';
import { createOpenApi } from 'better-supabase/openapi';
import { createOrpc } from 'better-supabase/orpc';
import { otel } from 'better-supabase/otel';
import { softDelete } from 'better-supabase/plugins/soft-delete';
import { tenant } from 'better-supabase/plugins/tenant';
import { timestamps } from 'better-supabase/plugins/timestamps';
import { createPostgres, postgresExecutor } from 'better-supabase/postgres';
import { createQueries, queryCache } from 'better-supabase/query';
import {
  createHooks,
  type LiveCountSeed,
  useLiveCount,
} from 'better-supabase/react';
import { defineTopic, liveCount } from 'better-supabase/realtime';
import {
  type Aal,
  checkAal,
  createServer,
  PRIMARY_COOKIE,
} from 'better-supabase/server';
import { defineBucket, type StoragePath } from 'better-supabase/storage';
import {
  defineSeed,
  expectTenantIsolation,
  testExecutor,
} from 'better-supabase/testing';
import { verifyWebhook } from 'better-supabase/webhooks';

import {
  type Database,
  type Functions,
  type Models,
  schema,
} from './generated.ts';

type Equal<A, B> =
  (<T>() => T extends A ? 1 : 2) extends <T>() => T extends B ? 1 : 2
    ? true
    : false;
const assert = <T extends true>(): T => true as T;

declare const client: SupabaseClient;

const logger: Logger = silentLogger;
const base = defineSupabase(schema, { logger })
  .use(timestamps())
  .use(softDelete())
  .use(tenant())
  .use(otel());

const customers = defineRepository(base, 'customers', (repo) => ({
  active: () =>
    repo.findMany({ where: { status: 'active' }, select: ['id', 'name'] }),
}));
export const sb = base.use(customers);

const db = sb.connect(client, { tenant: 'org' });

export async function reads(): Promise<void> {
  const rows = await db.customers
    .findMany({ select: ['id', 'status', 'createdAt'] })
    .orThrow();
  assert<
    Equal<
      (typeof rows)[number],
      { id: string; status: 'lead' | 'active' | 'archived'; createdAt: string }
    >
  >();

  const active = db.customers.active();
  assert<Equal<typeof active, AsyncResult<{ id: string; name: string }[]>>>();

  const withTags = await db.customers
    .findFirst({
      select: ['id'],
      include: { customerTags: { select: ['tagId'] } },
    })
    .orThrow();
  assert<
    Equal<
      typeof withTags,
      { id: string; customerTags: { tagId: string }[] } | null
    >
  >();

  const result: Result<unknown> = await db.tags.count();
  if (!result.ok) {
    const error: DbError = result.error;
    void error.kind;
  }

  // @ts-expect-error unknown column
  await db.customers.findMany({ select: ['nope'] });
  // @ts-expect-error the method exists on customers only
  db.tags.active();
  await db.customers.restore('id');
}

export function integrations(): unknown[] {
  const env = parseEnv({});
  const server = createServer(sb);
  const cache: CacheAdapter = memoryCache();
  sb.cache(cache);
  sb.cache(nextCache());
  sb.cache(queryCache(new QueryClient()));
  forwardMutations(sb, httpSink('https://example.com/events'), {
    source: '/crm',
  });
  const executor: Executor = postgresExecutor(
    createPostgres({ connectionString: 'postgres://x' }).admin,
  );
  const list = defineListQuery(sb, 'customers', {
    search: ['name'],
    facets: { status: 'status' },
    sorts: { name: [{ name: 'asc' }] },
    defaultSort: 'name',
  });
  const logos = defineBucket({
    id: 'customer-logos',
    path: '{orgId}/{customerId}/logo.webp',
  });
  const topic = defineTopic('org:{orgId}:customers');
  const seed = defineSeed(sb, {
    tags: { urgent: { organizationId: 'org', name: 'Urgent' } },
  });
  return [
    env,
    server,
    createNext(sb),
    createHono(sb),
    createOrpc(sb),
    createEdge(sb),
    createBrowser(sb),
    createHooks<
      ReturnType<typeof createBrowser<Models, Database, Functions, unknown>>
    >(),
    createQueries(sb, db),
    createOpenApi(sb, {
      info: { title: 'CRM', version: '1' },
      resources: { customers: true },
    }),
    defineConfig({ generators: [zod()] }),
    list,
    logos.path({
      orgId: 'o',
      customerId: 'c',
    }) satisfies StoragePath<'customer-logos'>,
    createImageLoader({ url: 'https://x.supabase.co' })({
      src: '/a.png',
      width: 64,
    }),
    topic,
    seed.sql(),
    verifyWebhook,
    testExecutor(executor, { sb }),
    expectTenantIsolation(sb, {
      tenants: [
        { id: 'a', claims: { sub: 'u1', org_id: 'a' } },
        { id: 'b', claims: { sub: 'u2', org_id: 'b' } },
      ],
      tables: {
        tags: {
          row: (tenant, n) => ({ organizationId: tenant.id, name: `t${n}` }),
          update: { name: 'changed' },
        },
      },
    }),
    sb.mapError((error) => new Error(error.message, { cause: error })),
    requireAal('aal2', { redirect: '/mfa' }),
    createNext(sb).route(() => Promise.resolve(ok(null)), { aal: 'aal2' }),
    createNext(sb)
      .session()
      .then((session) =>
        session.kind === 'user' ? (session.aal satisfies Aal) : undefined,
      ),
    checkAal,
    createNext(sb)
      .session()
      .then((session) => hasEntitlement(session, 'org', 'exports')),
    server
      .deleteAccount('u1', { buckets: [logos], cascades: ['customers'] })
      .map(({ removed }) => removed['customer-logos']),
    createServer(sb, { readUrl: false, replicas: { pinMs: 1000 } })
      .context(new Request('https://app.test/'))
      .then((ctx) => {
        ctx.replica?.pin();
        return ctx.replica?.wrote satisfies boolean | undefined;
      }),
    PRIMARY_COOKIE satisfies string,
    createNext(sb).liveCount(sb.spec.customers.count()) satisfies Promise<
      LiveCountSeed<'customers'>
    >,
    liveCount,
    useLiveCount,
    fromBetterResult(
      toBetterResult(
        { ok: true, data: 1, error: null },
        { ok: (value) => ({ status: 'ok', value }), err: (error) => error },
      ) satisfies BetterResultShape<number, DbError>,
    ) satisfies Result<number>,
  ];
}
