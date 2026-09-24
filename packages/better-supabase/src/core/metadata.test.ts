import type { SupabaseClient } from '@supabase/supabase-js';

import { describe, expect, it } from 'vitest';

import type { SchemaMeta } from '../schema/types.ts';

import { capturingClient, query } from '../fixtures/client.ts';
import { schema as camel } from '../fixtures/generated-camel.ts';
import { defineSchema } from '../schema/define.ts';
import { defineSupabase } from './define.ts';
import {
  DbException,
  dbError,
  isCheck,
  isConflict,
  isForeignKey,
} from './errors.ts';
import { AsyncResult } from './result.ts';

const meta: SchemaMeta = {
  version: 1,
  casing: 'camel',
  enums: {},
  functions: {},
  tables: {
    ledger: {
      key: 'ledger',
      name: 'ledger',
      schema: 'public',
      kind: 'table',
      columns: {
        id: {
          db: 'id',
          type: 'int8',
          nullable: false,
          hasDefault: true,
          generated: true,
          identity: 'always',
          codec: 'bigint',
        },
        code: { db: 'code', type: 'text', nullable: false, hasDefault: false },
        amount: {
          db: 'amount',
          type: 'numeric',
          nullable: false,
          hasDefault: false,
          codec: 'string',
        },
        bookedAt: {
          db: 'booked_at',
          type: 'timestamptz',
          nullable: false,
          hasDefault: true,
          codec: 'date',
        },
        total: {
          db: 'total',
          type: 'numeric',
          nullable: true,
          hasDefault: true,
          generated: true,
        },
      },
      primaryKey: ['id'],
      uniqueKeys: { ledger_code_key: ['code'] },
      relations: {},
      flags: {},
    },
  },
};

interface Ledger {
  create(row: object): AsyncResult<unknown>;
  update(id: unknown, patch: object): AsyncResult<unknown>;
  findMany(args?: object): AsyncResult<Record<string, unknown>[]>;
}

function ledger(client: SupabaseClient, schema: SchemaMeta = meta): Ledger {
  return defineSupabase(defineSchema(schema)).connect(client)[
    'ledger'
  ] as unknown as Ledger;
}

describe('read-only columns', () => {
  it('rejects writes to generated and identity always columns', async () => {
    const { client, requests } = capturingClient();
    const db = ledger(client);
    const insert = await db.create({
      id: 1n,
      code: 'a',
    });
    expect(insert.error).toMatchObject({
      kind: 'invalid_request',
      message: expect.stringContaining('"id" on "ledger" is read-only'),
    });
    const update = await db.update(1n, { total: 3 });
    expect(update.error?.message).toContain('(generated)');
    expect(requests).toHaveLength(0);
  });

  it('rejects updates to columns a view marks read-only', async () => {
    const view: SchemaMeta = {
      ...meta,
      tables: {
        ledger: {
          ...meta.tables['ledger']!,
          columns: {
            ...meta.tables['ledger']!.columns,
            code: {
              ...meta.tables['ledger']!.columns['code']!,
              updatable: false,
            },
          },
        },
      },
    };
    const { client } = capturingClient();
    const db = ledger(client, view);
    const result = await db.update(1n, { code: 'x' });
    expect(result.error?.message).toContain("can't be set in an update");
  });
});

describe('codecs', () => {
  it('casts exact columns to text and decodes rows', async () => {
    const { client, last } = capturingClient(() => ({
      body: [
        {
          id: '9007199254740993',
          code: 'a',
          amount: '10.10',
          bookedAt: '2026-09-24T10:00:00+00:00',
          total: 10.1,
        },
      ],
    }));
    const db = ledger(client);
    const [row] = await db.findMany().orThrow();
    expect(query(last())[0]).toBe(
      'select=id::text,code,amount::text,bookedAt:booked_at,total',
    );
    expect(row).toEqual({
      id: 9007199254740993n,
      code: 'a',
      amount: '10.10',
      bookedAt: new Date('2026-09-24T10:00:00Z'),
      total: 10.1,
    });
  });

  it('encodes Date and bigint values in filters and rows', async () => {
    const { client, requests } = capturingClient(() => ({ body: [] }));
    const db = ledger(client);
    await db.findMany({
      where: {
        id: 5n,
        bookedAt: { gte: new Date('2026-01-01T00:00:00Z') },
      },
    });
    expect(query(requests[0]!)).toContain('id=eq.5');
    expect(query(requests[0]!)).toContain(
      'booked_at=gte.2026-01-01T00:00:00.000Z',
    );
    await db.create({
      code: 'b',
      amount: '1.5',
      bookedAt: new Date('2026-02-01T00:00:00Z'),
    });
    expect(requests[1]!.body).toEqual({
      code: 'b',
      amount: '1.5',
      booked_at: '2026-02-01T00:00:00.000Z',
    });
  });
});

describe('findUnique', () => {
  it('looks rows up by a named unique key', async () => {
    const { client, last } = capturingClient(() => ({
      body: [{ id: 'c1', kvk: '123' }],
    }));
    const db = defineSupabase(camel).connect(client);
    const row = await db.customers
      .findUnique({
        where: { organizationId: 'o1', kvk: '123' },
        select: ['id', 'kvk'],
      })
      .orThrow();
    expect(row).toEqual({ id: 'c1', kvk: '123' });
    expect(query(last())).toEqual([
      'select=id,kvk',
      'organization_id=eq.o1',
      'kvk=eq.123',
      'limit=1',
    ]);
  });

  it('returns null when nothing matches and rejects partial keys', async () => {
    const { client } = capturingClient(() => ({ body: [] }));
    const db = defineSupabase(camel).connect(client);
    expect(
      await db.customers.findUnique({ where: { id: 'missing' } }).orThrow(),
    ).toBeNull();
    const partial = await db.customers.findUnique({
      where: { kvk: '1' } as never,
    });
    expect(partial.error?.message).toContain(
      'needs one complete unique key: { id }, { organizationId, kvk }',
    );
  });
});

describe('errors', () => {
  const conflict = dbError('conflict', 'duplicate', {
    constraint: 'customers_organization_id_kvk_key',
  });

  it('matches constraint predicates on errors and exceptions', () => {
    expect(isConflict(conflict)).toBe(true);
    expect(isConflict(conflict, 'customers_organization_id_kvk_key')).toBe(
      true,
    );
    expect(isConflict(new DbException(conflict), 'other')).toBe(false);
    expect(isCheck(conflict)).toBe(false);
    expect(
      isForeignKey(dbError('foreign_key', 'fk', { constraint: 'a_fkey' })),
    ).toBe(true);
    expect(isConflict('nope')).toBe(false);
  });

  it('throws a custom error from orThrow(factory)', async () => {
    class HttpError extends Error {
      readonly status: number;
      constructor(status: number) {
        super(`HTTP ${String(status)}`);
        this.status = status;
      }
    }
    await expect(
      AsyncResult.err(conflict).orThrow((error) => new HttpError(error.status)),
    ).rejects.toMatchObject({ status: 409 });
    await expect(AsyncResult.err(conflict).orThrow()).rejects.toBeInstanceOf(
      DbException,
    );
  });
});
