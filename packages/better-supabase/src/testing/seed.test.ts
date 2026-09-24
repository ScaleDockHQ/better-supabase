import { describe, expect, it } from 'vitest';

import { defineSupabase } from '../core/define.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { defineSeed, isSeed } from './seed.ts';

const sb = defineSupabase(schema);

describe('defineSeed', () => {
  it('renders parents first, with database names and literals', () => {
    const seed = defineSeed(sb, {
      customers: {
        acme: {
          id: 'c1',
          organizationId: 'o1',
          name: "O'Brien",
          metadata: { tier: 'pro' },
        },
        bare: { organizationId: 'o1', name: 'Bare' },
      },
      organizations: { one: { id: 'o1', name: 'One', slug: 'one' } },
    });
    expect(isSeed(seed)).toBe(true);
    const [organizations, customers] = seed.statements();
    expect(organizations).toBe(
      'insert into "public"."organizations" ("id", "name", "slug") values\n  (\'o1\', \'One\', \'one\')\non conflict do nothing;',
    );
    expect(customers).toContain(
      '("id", "organization_id", "name", "metadata")',
    );
    expect(customers).toContain(`('c1', 'o1', 'O''Brien', '{"tier":"pro"}')`);
    expect(customers).toContain("(default, 'o1', 'Bare', default)");
    expect(seed.rows.customers.acme.name).toBe("O'Brien");
  });

  it('renders arrays, dates, nulls and numbers', () => {
    const sql = defineSeed(sb, {
      organizations: { one: { id: 'o1', name: 'One', slug: 'one' } },
      customers: {
        one: { organizationId: 'o1', name: 'x', kvk: null },
      },
    }).sql();
    expect(sql).toContain("('o1', 'x', null)");

    const bad = defineSeed(sb, {
      organizations: { bad: { id: 'o1', name: 'x', nope: 1 } as never },
    });
    expect(() => bad.statements()).toThrow('unknown column "nope"');
  });

  it('quotes array elements and serialises dates', () => {
    const column = (db: string, type: string, extra: object = {}) => ({
      db,
      type,
      nullable: true,
      hasDefault: false,
      ...extra,
    });
    const fake = {
      meta: {
        version: 1,
        casing: 'snake',
        enums: {},
        functions: {},
        tables: {
          events: {
            key: 'events',
            name: 'events',
            schema: 'app',
            kind: 'table',
            primaryKey: [],
            uniqueKeys: {},
            relations: {},
            flags: {},
            columns: {
              tags: column('tags', 'text', { array: true }),
              at: column('at', 'timestamptz'),
              payload: column('payload', 'jsonb', { json: true }),
            },
          },
        },
      },
    };
    const sql = defineSeed(
      fake as never,
      {
        events: {
          one: {
            tags: ['a "b"', 'c\\d', null],
            at: new Date('2026-01-02T03:04:05.000Z'),
            payload: ['kept', 'as json'],
          },
        },
      } as never,
    ).sql();
    expect(sql).toContain(
      `('{"a \\"b\\"","c\\\\d",NULL}', '2026-01-02T03:04:05.000Z', '["kept","as json"]')`,
    );
  });

  it('rejects unknown tables at render time', () => {
    const seed = defineSeed(sb, { nope: {} } as never);
    expect(() => seed.sql()).toThrow('unknown table "nope"');
  });
});
