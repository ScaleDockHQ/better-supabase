import { describe, expect, it } from 'vitest';

import type { Operation } from '../ir/types.ts';
import type { ExecuteResult, Executor } from './executor.ts';

import { capturingClient } from '../fixtures/client.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { compileReadSet } from '../sql/read-sets.ts';
import { batchingExecutor } from './batch.ts';
import { defineSupabase } from './define.ts';
import { defineReadSet, readSetTables } from './read-set.ts';
import { ok, type Result } from './result.ts';

const sb = defineSupabase(schema);
const USER = '00000000-0000-0000-0000-000000000001';

const chrome = defineReadSet(
  sb,
  'app_chrome',
  { params: { orgId: 'uuid', kinds: 'text[]', search: 'text' } },
  (s, p) => ({
    customers: s.customers.findMany({
      select: ['id', 'name'],
      where: { organizationId: p.orgId, name: { contains: p.search } },
      orderBy: { name: 'asc' },
      limit: 5,
    }),
    calls: s.notes.count({
      where: {
        organizationId: p.orgId,
        kind: { in: p.kinds as readonly ('call' | 'email')[] },
      },
    }),
    first: s.customers.findFirst({
      select: ['id'],
      where: { organizationId: p.orgId, status: 'active' },
    }),
  }),
);

function fakeExecutor(): Executor & {
  batches: Operation[][];
  executed: Operation[];
} {
  const batches: Operation[][] = [];
  const executed: Operation[] = [];
  const answer = (op: Operation): Result<ExecuteResult> =>
    ok({
      rows: op.kind === 'select' && op.head ? [] : [{ id: op.table.key }],
      count: 3,
    });
  return {
    name: 'fake',
    batches,
    executed,
    execute: async (op) => {
      executed.push(op);
      return answer(op);
    },
    batch: async (ops) => {
      batches.push([...ops]);
      return ops.map(answer);
    },
  };
}

describe('defineReadSet', () => {
  it('rejects names that are not snake_case', () => {
    expect(() =>
      defineReadSet(sb, 'App-Chrome', {}, (s) => ({ all: s.tags.count() })),
    ).toThrow(/snake_case/);
  });

  it('rejects parameter types that are not plain type names', () => {
    expect(() =>
      defineReadSet(
        sb,
        'typed',
        { params: { id: 'uuid); drop table x; --' as 'uuid' } },
        (s) => ({ all: s.tags.count() }),
      ),
    ).toThrow(/invalid type/);
  });

  it('rejects entries that are not specs', () => {
    expect(() =>
      defineReadSet(sb, 'broken', {}, () => ({ nope: {} as never })),
    ).toThrow(/not a spec/);
  });

  it('lists every table the set reads', () => {
    expect(readSetTables(chrome).sort()).toEqual(['customers', 'notes']);
  });
});

describe('compileReadSet', () => {
  it('writes a stable, security invoker function that reads p', async () => {
    const { sql } = await compileReadSet(chrome);
    expect(sql).toContain(
      'create or replace function public.rs_app_chrome(p jsonb)',
    );
    expect(sql).toContain(
      "language sql stable security invoker set search_path = ''",
    );
    expect(sql).toContain("((p->>'orgId')::uuid)");
    expect(sql).toContain(
      "(array(select jsonb_array_elements_text(p->'kinds'))::text[])",
    );
    expect(sql).toContain("('%' || (p->>'search') || '%')");
    expect(sql).toContain("'active'");
    expect(sql).not.toMatch(/\$\d/);
    expect(sql).toContain(
      'grant execute on function public.rs_app_chrome(jsonb) to authenticated;',
    );
    expect(sql).not.toContain('to anon');
  });

  it('grants the roles the set lists', async () => {
    const open = defineReadSet(sb, 'open', { roles: ['anon'] }, (s) => ({
      tags: s.tags.count(),
    }));
    expect((await compileReadSet(open)).sql).toContain(
      'grant execute on function public.rs_open(jsonb) to anon;',
    );
  });

  it('refuses a placeholder used as the wrong shape', async () => {
    const wrong = defineReadSet(
      sb,
      'wrong',
      { params: { id: 'uuid' } },
      (s, p) => ({
        one: s.customers.count({ where: { id: { in: [p.id] } } }),
      }),
    );
    await expect(compileReadSet(wrong)).rejects.toThrow(/used as/);
  });
});

describe('db.$many over PostgREST', () => {
  it('runs a read set as one GET and decodes each entry', async () => {
    const { client, requests } = capturingClient(() => ({
      body: {
        customers: { rows: [{ id: 'c1', name: 'Acme' }], count: null },
        calls: { rows: [], count: 4 },
        first: { rows: [], count: null },
      },
    }));
    const db = sb.connect(client);
    const result = await db.$many(chrome, {
      orgId: USER,
      kinds: ['call'],
      search: 'ac',
    });
    expect(result.ok && result.data).toEqual({
      customers: [{ id: 'c1', name: 'Acme' }],
      calls: 4,
      first: null,
    });
    expect(requests).toHaveLength(1);
    expect(requests[0]!.method).toBe('GET');
    expect(requests[0]!.path).toBe('/rest/v1/rpc/rs_app_chrome');
    expect(JSON.parse(requests[0]!.params.get('p')!)).toEqual({
      orgId: USER,
      kinds: ['call'],
      search: 'ac',
    });
    expect(db.$stats().calls).toBe(1);
  });

  it('fails without calling the database when a parameter is missing', async () => {
    const { client, requests } = capturingClient();
    const result = await sb
      .connect(client)
      .$many(chrome, { orgId: USER } as never);
    expect(!result.ok && result.error.kind).toBe('invalid_request');
    expect(requests).toHaveLength(0);
  });

  it('runs ad-hoc specs in parallel and returns a tuple', async () => {
    const { client, requests } = capturingClient((request) =>
      request.path.endsWith('/tags')
        ? { body: [{ id: 't1' }] }
        : { body: [], headers: { 'content-range': '*/7' } },
    );
    const db = sb.connect(client);
    const result = await db.$many([
      sb.spec.tags.findMany({ select: ['id'] }),
      sb.spec.notes.count(),
    ]);
    expect(result.ok && result.data).toEqual([[{ id: 't1' }], 7]);
    expect(requests).toHaveLength(2);
    expect(db.$stats().waves).toBe(1);
  });
});

describe('db.$many with Executor.batch', () => {
  it('sends ad-hoc specs as one batch', async () => {
    const executor = fakeExecutor();
    const result = await sb
      .connect(executor)
      .$many([
        sb.spec.tags.findMany({ select: ['id'] }),
        sb.spec.notes.count(),
      ]);
    expect(result.ok && result.data).toEqual([[{ id: 'tags' }], 3]);
    expect(executor.batches).toHaveLength(1);
    expect(executor.batches[0]!.map((op) => op.table.key)).toEqual([
      'tags',
      'notes',
    ]);
    expect(executor.executed).toHaveLength(0);
  });

  it('binds read-set parameters instead of calling a function', async () => {
    const executor = fakeExecutor();
    const result = await sb.connect(executor).$many(chrome, {
      orgId: USER,
      kinds: ['call', 'email'],
      search: 'ac',
    });
    expect(result.ok).toBe(true);
    expect(executor.batches).toHaveLength(1);
    const text = JSON.stringify(executor.batches[0]);
    expect(text).toContain(USER);
    expect(text).toContain('email');
    expect(text).not.toContain('\\u0000');
  });
});

describe('batchingExecutor', () => {
  it('waits for every reader, and batches a second round separately', async () => {
    const executor = fakeExecutor();
    const batcher = batchingExecutor(
      executor as Executor & { batch: NonNullable<Executor['batch']> },
      2,
    );
    const op = await captureOp();
    const context = { errorMappers: [] };
    const first = (async () => {
      await batcher.executor.execute(op, context);
      await batcher.executor.execute(op, context);
      batcher.done();
    })();
    const second = (async () => {
      await batcher.executor.execute(op, context);
      batcher.done();
    })();
    await Promise.all([first, second]);
    expect(executor.batches.map((batch) => batch.length)).toEqual([2, 1]);
  });
});

async function captureOp(): Promise<Operation> {
  let seen: Operation | undefined;
  await sb
    .connect({
      name: 'capture',
      execute: async (op) => {
        seen = op;
        return ok({ rows: [], count: 0 });
      },
    })
    .tags.count();
  return seen!;
}
