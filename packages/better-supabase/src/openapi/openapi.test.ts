import { describe, expect, it } from 'vitest';

import { defineSupabase } from '../core/define.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { defineListQuery } from '../list/index.ts';
import { createOpenApi } from './index.ts';

const sb = defineSupabase(schema);
const customerList = defineListQuery(sb, 'customers', {
  search: ['name'],
  facets: { status: 'status' },
  sorts: { name: { name: 'asc' } },
  defaultSort: 'name',
});

const doc = createOpenApi(sb, {
  info: { title: 'CRM', version: '1.0.0' },
  basePath: '/api',
  resources: {
    customers: { list: customerList },
    notes: { operations: ['list', 'get'] },
  },
  security: ['bearer', 'oauth2'],
  supabaseUrl: 'https://abc.supabase.co',
});

function refs(value: unknown, out: string[] = []): string[] {
  if (Array.isArray(value)) for (const item of value) refs(item, out);
  else if (value && typeof value === 'object') {
    for (const [key, item] of Object.entries(value)) {
      if (key === '$ref' && typeof item === 'string') out.push(item);
      else refs(item, out);
    }
  }
  return out;
}

describe('createOpenApi', () => {
  it('describes resources as OpenAPI 3.1', () => {
    expect(doc.openapi).toBe('3.1.1');
    expect(Object.keys(doc.paths)).toEqual([
      '/api/customers',
      '/api/customers/{id}',
      '/api/notes',
      '/api/notes/{id}',
    ]);
    expect(Object.keys(doc.paths['/api/customers']!)).toEqual(['get', 'post']);
    expect(Object.keys(doc.paths['/api/customers/{id}']!)).toEqual([
      'parameters',
      'get',
      'patch',
      'delete',
    ]);
    expect(Object.keys(doc.paths['/api/notes/{id}']!)).toEqual([
      'parameters',
      'get',
    ]);
    expect(doc.paths['/api/customers/{id}']).toMatchObject({
      parameters: [
        {
          name: 'id',
          in: 'path',
          required: true,
          schema: { type: 'string', format: 'uuid' },
        },
      ],
      delete: {
        operationId: 'deleteCustomers',
        'x-better-supabase-table': 'public.customers',
        responses: { '204': {} },
      },
    });
  });

  it('uses list-query parameters and page schemas', () => {
    const list = doc.paths['/api/customers']!['get'] as {
      parameters: { name: string }[];
    };
    expect(list.parameters.map((parameter) => parameter.name)).toEqual([
      'q',
      'sort',
      'page',
      'size',
      'status',
    ]);
    expect(doc.components.schemas['CustomersPage']).toMatchObject({
      properties: {
        items: { items: { $ref: '#/components/schemas/CustomersRow' } },
      },
    });
    expect(doc.components.schemas['CustomersInsert']).toMatchObject({
      required: expect.arrayContaining(['name']),
    });
  });

  it('declares Supabase security and Problem Details errors', () => {
    expect(doc.components.securitySchemes).toMatchObject({
      supabaseJwt: { type: 'http', scheme: 'bearer' },
      supabaseOAuth: {
        flows: {
          authorizationCode: {
            tokenUrl: 'https://abc.supabase.co/auth/v1/oauth/token',
          },
        },
      },
    });
    expect(doc.security).toEqual([{ supabaseJwt: [] }, { supabaseOAuth: [] }]);
    expect(doc.components.responses['Conflict']).toMatchObject({
      content: {
        'application/problem+json': {
          schema: { $ref: '#/components/schemas/Problem' },
        },
      },
    });
  });

  it('only references components that exist', () => {
    const components = doc.components as Record<
      string,
      Record<string, unknown>
    >;
    const missing = refs(doc).filter((target) => {
      const [, section, name] =
        /^#\/components\/(\w+)\/(\w+)$/.exec(target) ?? [];
      return components[section!]?.[name!] === undefined;
    });
    expect(refs(doc).length).toBeGreaterThan(10);
    expect(missing).toEqual([]);
  });

  it('rejects unknown tables and oauth2 without a URL', () => {
    expect(() =>
      createOpenApi(sb, {
        info: { title: 'x', version: '1' },
        resources: { nope: true },
      }),
    ).toThrow('unknown table "nope"');
    expect(() =>
      createOpenApi(sb, {
        info: { title: 'x', version: '1' },
        resources: {},
        security: ['oauth2'],
      }),
    ).toThrow('needs supabaseUrl');
  });
});
