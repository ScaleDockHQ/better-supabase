import { describe, expect, it } from 'vitest';

import { defineSupabase } from '../core/define.ts';
import { capturingClient } from '../fixtures/client.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { defineListQuery, UNSET } from './index.ts';

const sb = defineSupabase(schema);
const list = defineListQuery(sb, 'customers', {
  search: ['name', 'kvk'],
  facets: { status: 'status', kvk: 'kvk' },
  sorts: {
    name: { name: 'asc' },
    newest: [{ createdAt: 'desc' }, { id: 'asc' }],
  },
  defaultSort: 'newest',
  pageSize: 25,
});

describe('defineListQuery', () => {
  it('parses URL params with defaults, comma lists and repeated keys', () => {
    const result = list.parse(
      new URLSearchParams('q=  road  &status=active,lead&status=active&page=2'),
    );
    expect(result).toEqual({
      ok: true,
      value: {
        q: 'road',
        sort: 'newest',
        page: 2,
        size: 25,
        facets: { status: ['active', 'lead'] },
      },
    });
    expect(list.parse({ sort: 'name', size: '10' })).toMatchObject({
      ok: true,
      value: { sort: 'name', size: 10 },
    });
    expect(list.parse(undefined)).toEqual({ ok: true, value: list.defaults });
  });

  it('parses typed input', () => {
    expect(
      list.parse({ q: 'x', facets: { status: ['archived'] }, page: 3 }),
    ).toMatchObject({
      ok: true,
      value: { q: 'x', page: 3, facets: { status: ['archived'] } },
    });
  });

  it('reports every problem with a path', () => {
    const result = list.parse(
      new URLSearchParams(`sort=oldest&page=0&size=500&status=bogus,${UNSET}`),
    );
    expect(result.issues?.map((issue) => issue.path)).toEqual([
      ['sort'],
      ['page'],
      ['size'],
      ['facets', 'status'],
      ['facets', 'status'],
    ]);
    expect(list.parse({ q: 'x'.repeat(201) }).issues).toEqual([
      { message: 'At most 200 characters', path: ['q'] },
    ]);
  });

  it('round-trips through URL params, leaving out defaults', () => {
    const query = list.parse({
      q: 'a,b',
      sort: 'name',
      facets: { kvk: [UNSET, '1001'] },
    }).value!;
    const params = list.toSearchParams(query);
    expect(params.toString()).toBe('q=a%2Cb&sort=name&kvk=__unset__%2C1001');
    expect(list.parse(params).value).toEqual({
      ...query,
      facets: { kvk: [UNSET, '1001'] },
    });
    expect(list.toSearchParams(list.defaults).toString()).toBe('');
  });

  it('compiles to safe PostgREST filters and merges extra arguments', async () => {
    const { client, last } = capturingClient((request) => ({
      body: [{ id: 'c1', name: 'Acme' }],
      headers: request.headers.get('prefer')?.includes('count')
        ? { 'content-range': '0-0/1' }
        : {},
    }));
    const db = sb.connect(client);
    const query = list.parse({
      q: 'o,(x)',
      facets: { status: ['active'], kvk: [UNSET, '1001'] },
    }).value!;
    const page = await list
      .run(db, query, {
        select: ['id', 'name'],
        where: { organizationId: 'org-1' },
      })
      .orThrow();
    expect(page).toEqual({
      items: [{ id: 'c1', name: 'Acme' }],
      page: { number: 1, size: 25, total: 1, pages: 1, hasMore: false },
    });
    const params = last().params;
    expect(params.get('organization_id')).toBe('eq.org-1');
    expect(params.getAll('or')).toEqual([
      '(name.ilike."%o,(x)%",kvk.ilike."%o,(x)%")',
      '(kvk.in.("1001"),kvk.is.null)',
    ]);
    expect(params.get('status')).toBe('in.("active")');
    expect(params.get('order')).toBe('created_at.desc,id.asc');
    expect(params.get('limit')).toBe('26');
  });

  it('counts facet values next to the page in one wave', async () => {
    const faceted = defineListQuery(sb, 'customers', {
      search: ['name'],
      facets: { status: 'status', kvk: 'kvk' },
      sorts: { name: { name: 'asc' } },
      defaultSort: 'name',
      facetCounts: true,
      count: 'planned',
    });
    const { client, requests } = capturingClient((request) =>
      request.params.get('select')?.includes('count()')
        ? {
            body: [
              { status: 'active', kvk: '1001', _count: 3 },
              { status: 'active', kvk: null, _count: 2 },
              { status: 'lead', kvk: '1001', _count: 4 },
              { status: 'lead', kvk: '2002', _count: 5 },
            ],
          }
        : { body: [{ id: 'c1' }], headers: { 'content-range': '0-0/1' } },
    );
    const db = sb.connect(client);
    const query = faceted.parse({
      q: 'acme',
      facets: { status: ['active'] },
    }).value!;
    const page = await faceted
      .run(db, query, { select: ['id'], where: { organizationId: 'org-1' } })
      .orThrow();
    expect(page.facetCounts).toEqual({
      status: { active: 5, lead: 9, archived: 0 },
      kvk: { '1001': 3, [UNSET]: 2 },
    });
    expect(db.$stats()).toMatchObject({ calls: 2, waves: 1 });

    const [pageRequest, groupRequest] = requests;
    expect(pageRequest!.headers.get('prefer')).toContain('count=planned');
    expect(pageRequest!.params.get('status')).toBe('in.("active")');
    expect(groupRequest!.params.get('status')).toBeNull();
    expect(groupRequest!.params.get('organization_id')).toBe('eq.org-1');
    expect(groupRequest!.params.toString()).toContain('acme');

    await faceted.run(db, query, { count: 'estimated' }).orThrow();
    expect(requests[2]!.headers.get('prefer')).toContain('count=estimated');
  });

  it('fails the run when the facet counts fail', async () => {
    const faceted = defineListQuery(sb, 'customers', {
      facets: { status: 'status' },
      sorts: { name: { name: 'asc' } },
      defaultSort: 'name',
      facetCounts: true,
    });
    const { client } = capturingClient((request) =>
      request.params.get('select')?.includes('count()')
        ? {
            status: 400,
            body: {
              code: 'PGRST123',
              message: 'Use of aggregate functions is not allowed',
            },
          }
        : { body: [] },
    );
    const result = await faceted.run(sb.connect(client), faceted.defaults);
    expect(result.ok).toBe(false);
  });

  it('describes itself for OpenAPI, JSON Schema and UIs', () => {
    expect(list.openapi.map((parameter) => parameter.name)).toEqual([
      'q',
      'sort',
      'page',
      'size',
      'status',
      'kvk',
    ]);
    expect(
      list.openapi.find((parameter) => parameter.name === 'status'),
    ).toMatchObject({
      style: 'form',
      explode: false,
      schema: {
        type: 'array',
        items: { enum: ['lead', 'active', 'archived'] },
      },
    });
    expect(list.jsonSchema).toMatchObject({
      properties: {
        sort: { enum: ['name', 'newest'], default: 'newest' },
        facets: { properties: { kvk: { items: { type: 'string' } } } },
      },
    });
    expect(list.facets).toEqual([
      {
        key: 'status',
        column: 'status',
        nullable: false,
        values: ['lead', 'active', 'archived'],
      },
      { key: 'kvk', column: 'kvk', nullable: true },
    ]);
  });

  it('is a Standard Schema and builds nuqs parsers', async () => {
    const outcome = await list.schema['~standard'].validate({ sort: 'name' });
    expect(outcome).toMatchObject({ value: { sort: 'name' } });
    const created: unknown[] = [];
    const parsers = list.nuqs((spec) => {
      created.push(spec);
      return { spec };
    });
    expect(Object.keys(parsers)).toEqual([
      'q',
      'sort',
      'page',
      'size',
      'status',
      'kvk',
    ]);
    expect(list.parsers.status.parse('a, b')).toEqual(['a', 'b']);
    expect(list.parsers.sort.parse('oldest')).toBeNull();
  });

  it('rejects broken definitions', () => {
    expect(() =>
      defineListQuery(sb, 'customers', {
        sorts: { name: { name: 'asc' } },
        defaultSort: 'nope' as 'name',
      }),
    ).toThrow(/defaultSort/);
    expect(() =>
      defineListQuery(sb, 'customers', {
        facets: { page: 'status' },
        sorts: { name: { name: 'asc' } },
        defaultSort: 'name',
      }),
    ).toThrow(/reserved/);
  });
});
