import { describe, expect, it } from 'vitest';

import type { Executor } from './executor.ts';
import type { Logger } from './logger.ts';

import { schema } from '../fixtures/generated-camel.ts';
import { tenant } from '../plugins/tenant/index.ts';
import { memoryCache } from './cache.ts';
import { defineRepository } from './define-repository.ts';
import { defineSupabase } from './define.ts';
import { definePlugin } from './plugin.ts';
import { ok } from './result.ts';

const ACME = '00000000-0000-4000-8000-000000000001';

function echo(): Executor {
  return {
    name: 'echo',
    execute: (op) => {
      if (op.kind === 'insert')
        return Promise.resolve(
          ok({ rows: op.rows.map((row) => ({ ...row })), count: null }),
        );
      if (op.kind === 'delete' || op.kind === 'update')
        return Promise.resolve(ok({ rows: [{ id: 't1' }], count: null }));
      return Promise.resolve(ok({ rows: [{ id: 't1', name: 'a' }], count: 1 }));
    },
  };
}

function recordingLogger(): Logger & { readonly messages: string[] } {
  const messages: string[] = [];
  const record = (message: string): void => void messages.push(message);
  return { messages, debug: record, info: record, warn: record, error: record };
}

describe('sb.cache', () => {
  it('invalidates the table, cascaded tables, row keys and tenant after mutations', async () => {
    const sb = defineSupabase(schema).use(tenant());
    const cache = memoryCache();
    const detach = sb.cache(cache);
    const db = sb.connect(echo(), { tenant: ACME });

    await db.tags
      .create({ id: 't1', name: 'a', organizationId: ACME })
      .orThrow();
    await db.tags.delete('t1').orThrow();
    await db.tags.findMany({ limit: 1 }).orThrow();
    expect(cache.invalidated).toEqual([
      { table: 'tags', tables: ['tags'], ids: ['t1'], tenant: ACME },
      {
        table: 'tags',
        tables: ['tags', 'customerTags'],
        ids: ['t1'],
        tenant: ACME,
      },
    ]);

    detach();
    await db.tags
      .create({ id: 't2', name: 'b', organizationId: ACME })
      .orThrow();
    expect(cache.invalidated).toHaveLength(2);
  });

  it('logs adapter failures without failing the mutation', async () => {
    const logger = recordingLogger();
    const sb = defineSupabase(schema, { logger });
    sb.cache({
      name: 'sync',
      invalidate: () => {
        throw new Error('down');
      },
    });
    sb.cache({
      name: 'async',
      invalidate: () => Promise.reject(new Error('down')),
    });

    const created = await sb
      .connect(echo())
      .tags.create({ id: 't1', name: 'a', organizationId: ACME });
    await Promise.resolve();
    expect(created.ok).toBe(true);
    expect(logger.messages).toEqual([
      'cache adapter "sync" failed',
      'cache adapter "async" failed',
    ]);
  });
});

describe('logger', () => {
  it('receives event handler and afterMutation failures', async () => {
    const logger = recordingLogger();
    const sb = defineSupabase(schema, { logger }).use(
      definePlugin({
        name: 'noisy',
        afterMutation: () => {
          throw new Error('hook');
        },
      }),
    );
    sb.on('query', () => {
      throw new Error('handler');
    });
    const result = await sb
      .connect(echo())
      .tags.create({ id: 't1', name: 'a', organizationId: ACME });
    expect(result.ok).toBe(true);
    expect(logger.messages).toEqual([
      '"query" handler threw',
      'plugin "noisy" afterMutation threw',
    ]);
  });
});

describe('defineRepository', () => {
  const base = defineSupabase(schema);

  it('adds methods to one table only', async () => {
    const tags = defineRepository(base, 'tags', (repo) => ({
      named: (name: string) => repo.findFirst({ where: { name } }),
    }));
    expect(tags.name).toBe('repository:tags');
    const db = base.use(tags).connect(echo());
    await expect(db.tags.named('a').orThrow()).resolves.toEqual({
      id: 't1',
      name: 'a',
    });
    expect('named' in db.customers).toBe(false);
  });

  it('sees methods from other plugins and rejects clashes and unknown tables', () => {
    const scoped = defineRepository(base, 'tags', (repo) => ({
      all: () => repo.findMany({}),
    }));
    const clash = defineRepository(base, 'tags', () => ({ findMany: () => 1 }));
    expect(() => base.use(scoped).use(clash)).toThrow(/already installed/);
    expect(() => base.use(clash).connect(echo()).tags).toThrow(
      /redefines "tags.findMany"/,
    );
    // @ts-expect-error unknown table
    expect(() => defineRepository(base, 'nope', () => ({}))).toThrow(
      /unknown table "nope"/,
    );
  });
});
