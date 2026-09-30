import { describe, expect, it } from 'vitest';

import fixture from '../../fixtures/snapshot.json' with { type: 'json' };
import { parseSnapshot } from '../commands/snapshot.ts';
import { toCatalog } from './catalog.ts';
import { fromCatalog } from './from-catalog.ts';
import { managementSource } from './source.ts';
import { stabilizeMetadata } from './typegen.ts';

const snapshot = parseSnapshot(fixture);

describe('managementSource', () => {
  it('posts SQL to the read-only endpoint and returns the rows', async () => {
    const calls: { url: string; init: RequestInit }[] = [];
    const source = managementSource({
      projectRef: 'abc',
      accessToken: 'sbp_token',
      fetch: (async (url: string, init: RequestInit) => {
        calls.push({ url, init });
        return new Response(JSON.stringify([{ one: 1 }]));
      }) as typeof fetch,
    });
    expect(await source.queryable.query('select 1 as one')).toEqual({
      rows: [{ one: 1 }],
    });
    expect(calls[0]!.url).toBe(
      'https://api.supabase.com/v1/projects/abc/database/query/read-only',
    );
    expect(calls[0]!.init.headers).toMatchObject({
      authorization: 'Bearer sbp_token',
    });
    expect(JSON.parse(calls[0]!.init.body as string)).toEqual({
      query: 'select 1 as one',
    });
  });

  it('reports API errors with the status', async () => {
    const source = managementSource({
      projectRef: 'abc',
      accessToken: 'bad',
      fetch: async () =>
        new Response('{"message":"Unauthorized"}', {
          status: 401,
        }),
    });
    await expect(source.queryable.query('select 1')).rejects.toThrow(
      /\(401\) for project abc/,
    );
  });
});

describe('toCatalog', () => {
  const catalog = toCatalog(snapshot);
  const customers = catalog.tables.find(
    (table) => table.schema === 'public' && table.name === 'customers',
  )!;

  it('joins typegen metadata with the extras', () => {
    expect(customers.kind).toBe('table');
    expect(customers.rls).toBe(true);
    expect(customers.primaryKey).toEqual(['id']);
    expect(customers.uniques.map((unique) => unique.name)).toContain(
      'customers_organization_id_kvk_key',
    );
    expect(
      customers.foreignKeys.find(
        (fk) => fk.name === 'customers_organization_id_fkey',
      ),
    ).toMatchObject({
      refTable: 'organizations',
      onDelete: 'cascade',
      oneToOne: false,
    });
  });

  it('normalizes columns', () => {
    const id = customers.columns.find((column) => column.name === 'id')!;
    expect(id).toMatchObject({ udt: 'uuid', isArray: false, hasDefault: true });
    expect(catalog.enums.map((entry) => entry.name)).toContain('note_kind');
  });

  it('keeps functions with their signature and search_path', () => {
    const fn = catalog.functions.find(
      (entry) => entry.name === 'current_tenant_id',
    )!;
    expect(fn).toMatchObject({
      schema: 'better_supabase',
      volatility: 'stable',
      searchPath: '',
    });
  });
});

describe('fromCatalog', () => {
  it('round-trips tables through a snapshot', () => {
    const catalog = toCatalog(snapshot);
    expect(toCatalog(fromCatalog(catalog)).tables).toEqual(catalog.tables);
  });
});

describe('stabilizeMetadata', () => {
  it('derives ids from names, so oids do not leak into snapshots', () => {
    const shifted = structuredClone(snapshot.generator);
    for (const table of shifted.tables) table.id += 500;
    for (const column of shifted.columns) column.table_id += 500;
    for (const key of shifted.primaryKeys) key.table_id += 500;
    expect(stabilizeMetadata(shifted).metadata).toEqual(
      stabilizeMetadata(snapshot.generator).metadata,
    );
  });
});
