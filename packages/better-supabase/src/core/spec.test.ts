import { describe, expect, it } from 'vitest';

import type { Executor } from './executor.ts';

import { capturingClient, query } from '../fixtures/client.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { invalidationTargets } from '../ir/tables.ts';
import { memoryCache } from './cache.ts';
import { defineSupabase } from './define.ts';
import { ok } from './result.ts';

const sb = defineSupabase(schema);

describe('QuerySpec', () => {
  it('is plain JSON that round-trips', () => {
    const spec = sb.spec.customers.findMany({
      select: ['id', 'name'],
      where: { status: 'active' },
      limit: 5,
    });
    expect(spec).toEqual({
      v: 1,
      table: 'customers',
      method: 'findMany',
      args: [{ select: ['id', 'name'], where: { status: 'active' }, limit: 5 }],
    });
    expect(JSON.parse(JSON.stringify(spec))).toEqual(spec);
    expect(sb.spec.customers.findMany()).toEqual({
      v: 1,
      table: 'customers',
      method: 'findMany',
      args: [],
    });
  });

  it('runs through db.$run with the same request as the repository', async () => {
    const { client, requests } = capturingClient(() => ({
      body: [{ id: 'c1', name: 'Acme' }],
    }));
    const db = sb.connect(client);
    const spec = sb.spec.customers.findById('c1', { select: ['id', 'name'] });
    const viaSpec = await db.$run(
      JSON.parse(JSON.stringify(spec)) as typeof spec,
    );
    const direct = await db.customers.findById('c1', {
      select: ['id', 'name'],
    });
    expect(viaSpec).toEqual(direct);
    expect(query(requests[0]!)).toEqual(query(requests[1]!));
  });

  it('passes the abort signal into the method arguments', async () => {
    const controller = new AbortController();
    controller.abort();
    const { client } = capturingClient();
    const result = await sb
      .connect(client)
      .$run(sb.spec.customers.count(), { signal: controller.signal });
    expect(result.ok).toBe(false);
  });

  it('rejects values that are not specs', async () => {
    const { client } = capturingClient();
    const db = sb.connect(client);
    const result = await db.$run({
      v: 1,
      table: 'customers',
      method: 'delete',
      args: [],
    } as never);
    expect(result.error?.kind).toBe('invalid_request');
  });
});

describe('touched tables', () => {
  it('collects includes and relation filters', () => {
    const spec = sb.spec.customers.findMany({
      select: ['id'],
      include: { notes: { select: ['id'] } },
      where: { organization: { is: { slug: 'acme' } } },
    });
    expect(sb.tablesOf(spec).sort()).toEqual(
      ['customers', 'notes', 'organizations'].sort(),
    );
  });

  it('ignores the selection of counts', () => {
    expect(
      sb.tablesOf(
        sb.spec.customers.count({
          where: { customerTags: { some: { tagId: 't' } } },
        }),
      ),
    ).toEqual(['customers', 'customerTags']);
  });

  it('falls back to the spec table when the arguments are invalid', () => {
    expect(
      sb.tablesOf(
        sb.spec.customers.findMany({ include: { nope: true } } as never),
      ),
    ).toEqual(['customers']);
  });
});

describe('invalidation targets', () => {
  it('follows cascades and set-null foreign keys from the deleted table', () => {
    expect(invalidationTargets(sb.meta, 'tags')).toEqual([
      'tags',
      'customerTags',
    ]);
    const fromCustomers = invalidationTargets(sb.meta, 'customers');
    expect(fromCustomers[0]).toBe('customers');
    expect(fromCustomers).toContain('notes');
    expect(fromCustomers).toContain('customerTags');
  });
});

describe('defineRpc', () => {
  const rpcExecutor: Executor = {
    name: 'rpc',
    execute: () => Promise.resolve(ok({ rows: [], count: null })),
    rpc: () => Promise.resolve(ok(null)),
  };

  it('invalidates the declared tables after a successful call', async () => {
    const withRpc = sb.defineRpc('archive_customer' as never, {
      invalidates: ['customers'],
    });
    const cache = memoryCache();
    withRpc.cache(cache);
    await (
      withRpc.connect(rpcExecutor).$rpc as unknown as (
        name: string,
      ) => Promise<unknown>
    )('archive_customer');
    expect(cache.invalidated).toEqual([
      {
        table: 'customers',
        tables: invalidationTargets(sb.meta, 'customers'),
        ids: [],
      },
    ]);
    await (
      withRpc.connect(rpcExecutor).$rpc as unknown as (
        name: string,
      ) => Promise<unknown>
    )('other_function');
    expect(cache.invalidated).toHaveLength(1);
  });

  it('rejects unknown tables', () => {
    expect(() =>
      sb.defineRpc('archive_customer' as never, {
        invalidates: ['nope' as never],
      }),
    ).toThrow('invalidates unknown table "nope"');
  });
});
