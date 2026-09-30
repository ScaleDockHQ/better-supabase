import { afterEach, describe, expect, it, vi } from 'vitest';

import { defineSupabase } from '../../core/define.ts';
import { definePlugin } from '../../core/plugin.ts';
import { capturingClient } from '../../fixtures/client.ts';
import { schema } from '../../fixtures/generated-camel.ts';
import { defineSchema } from '../../schema/define.ts';
import { tenant } from '../tenant/index.ts';
import {
  recommended,
  rules,
  type RuleViolation,
  safe,
  strict,
} from './index.ts';

function withReport(set = strict()) {
  const violations: RuleViolation[] = [];
  const plugin = rules({ rules: set, report: (v) => violations.push(v) });
  return { plugin, violations };
}

const context = { tenant: 'org-1' };

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('rules()', () => {
  it('fails unbounded, oversized and deep reads under strict()', async () => {
    const { plugin, violations } = withReport();
    const { client, requests } = capturingClient();
    const db = defineSupabase(schema).use(plugin).connect(client, context);

    const unbounded = await db.customers.findMany();
    expect(unbounded.error).toMatchObject({
      kind: 'invalid_request',
      message: expect.stringContaining('noUnboundedFindMany'),
    });
    await db.customers.findMany({ limit: 5000, orderBy: { name: 'asc' } });
    await db.customers.findMany({
      limit: 1,
      include: {
        customerTags: {
          include: {
            tag: { include: { customerTags: { include: { customer: true } } } },
          },
        },
      },
    });
    expect(violations.map((v) => v.rule)).toEqual([
      'noUnboundedFindMany',
      'maxLimit',
      'maxIncludeDepth',
    ]);
    expect(requests).toHaveLength(0);

    const fine = await db.customers.findMany({
      limit: 10,
      orderBy: { name: 'asc' },
    });
    expect(fine.error).toBeNull();
    await db.customers.findById('c1');
    await db.customers.count();
    expect(violations).toHaveLength(3);
  });

  it('reports warnings without failing the call', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const { client, requests } = capturingClient();
    const db = defineSupabase(schema)
      .use(rules({ rules: recommended() }))
      .connect(client, context);
    const result = await db.customers.findMany();
    expect(result.error).toBeNull();
    expect(requests).toHaveLength(1);
    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining('noUnboundedFindMany (customers)'),
    );
    warn.mockRestore();
  });

  it('sees the query before other plugins scope it', async () => {
    const { plugin, violations } = withReport(safe());
    const { client } = capturingClient();
    const db = defineSupabase(schema)
      .use(tenant({ onMissing: 'skip' }))
      .use(plugin)
      .connect(client);
    const result = await db.customers.findMany({ limit: 1 });
    expect(result.error?.message).toContain('requireTenantContext');
    expect(violations[0]).toMatchObject({
      rule: 'requireTenantContext',
      table: 'customers',
      operation: 'select',
    });

    const claims = db.$with({ claims: { tenant_id: 'org-1' } });
    expect((await claims.customers.findMany({ limit: 1 })).error).toBeNull();
    const service = db.$with({
      actor: { id: 'service', kind: 'service' },
    });
    expect((await service.customers.findMany({ limit: 1 })).error).toBeNull();
  });

  it('refuses service connections in a browser', async () => {
    vi.stubGlobal('window', {});
    vi.stubGlobal('document', {});
    const { plugin } = withReport(safe());
    const { client } = capturingClient();
    const db = defineSupabase(schema)
      .use(plugin)
      .connect(client, {
        actor: { id: 'service', kind: 'service' },
      });
    const result = await db.tags.findMany({ limit: 1 });
    expect(result.error?.message).toContain('noAdminInBrowser');
  });

  it('guards sensitive columns unless the call opts in', async () => {
    const meta = schema.meta;
    const contacts = meta.tables['contacts']!;
    const marked = defineSchema({
      ...meta,
      tables: {
        ...meta.tables,
        contacts: {
          ...contacts,
          columns: {
            ...contacts.columns,
            email: { ...contacts.columns['email']!, sensitive: true },
          },
        },
      },
    });
    const { plugin } = withReport(safe());
    const { client } = capturingClient();
    const db = defineSupabase({ ...schema, meta: marked.meta })
      .use(plugin)
      .connect(client, context);
    const denied = await db.contacts.findMany({ limit: 1 });
    expect(denied.error?.message).toContain('contacts.email');
    const named = await db.contacts.findMany({ select: ['id'], limit: 1 });
    expect(named.error).toBeNull();
    const allowed = await db.contacts.findMany({ limit: 1, sensitive: true });
    expect(allowed.error).toBeNull();
  });

  it('flags storage objects written to *_url columns', async () => {
    const meta = schema.meta;
    const customers = meta.tables['customers']!;
    const text = { type: 'text', nullable: true, hasDefault: false } as const;
    const marked = defineSchema({
      ...meta,
      tables: {
        ...meta.tables,
        customers: {
          ...customers,
          columns: {
            ...customers.columns,
            logoUrl: { ...text, db: 'logo_url' },
            bannerUrl: { ...text, db: 'banner_url', storage: 'banners' },
          },
        },
      },
    });
    const { plugin, violations } = withReport(recommended());
    const { client } = capturingClient();
    const db = defineSupabase({ ...schema, meta: marked.meta })
      .use(plugin)
      .connect(client, context);
    const write = (set: Record<string, string>) =>
      db.customers.update('c1', set);
    await write({ logoUrl: 'o1/c1/logo/1.webp' });
    await write({
      logoUrl:
        'https://abcdefghijklmnopqrst.supabase.co/storage/v1/object/sign/a/b.png?token=t',
    });
    await write({ logoUrl: 'https://example.com/logo.png' });
    await write({ name: 'Acme' });
    await db.customers.create({
      organizationId: 'org-1',
      name: 'Acme',
      bannerUrl: 'o1/banner.png',
    } as never);
    expect(
      violations.map((v) => [v.rule, v.level, v.operation, v.message]),
    ).toEqual([
      [
        'storagePathColumns',
        'warn',
        'update',
        expect.stringContaining('store its path in "logo_path"'),
      ],
      ['storagePathColumns', 'warn', 'update', expect.any(String)],
      [
        'storagePathColumns',
        'warn',
        'insert',
        '"banner_url" holds paths in bucket "banners"; name it "banner_path"',
      ],
    ]);
  });

  it('keeps the repository guard for deleteMany without where', async () => {
    const { plugin, violations } = withReport(safe());
    const { client } = capturingClient();
    const db = defineSupabase(schema).use(plugin).connect(client, context);
    const result = await db.tags.deleteMany({} as never);
    expect(result.error?.kind).toBe('invalid_request');
    expect(violations.map((v) => v.rule)).toEqual([]);
  });
});

describe('db.$table and db.$withoutPlugins', () => {
  it('looks repositories up by name', async () => {
    const { client } = capturingClient();
    const db = defineSupabase(schema).connect(client);
    expect(db.$table('tags')).toBe(db.tags);
    expect(() => db.$table('nope' as 'tags')).toThrow('unknown table "nope"');
  });

  it('drops plugins, including executor wrappers', async () => {
    const wrapped = vi.fn();
    const { client, requests } = capturingClient();
    const db = defineSupabase(schema)
      .use(rules({ rules: strict(), report: () => {} }))
      .use(
        definePlugin({
          name: 'wrap',
          wrapExecutor: (executor) => ({
            name: 'wrap',
            execute: (op, ctx) => {
              wrapped();
              return executor.execute(op, ctx);
            },
          }),
        }),
      )
      .connect(client, context);
    expect((await db.tags.findMany()).error?.kind).toBe('invalid_request');
    const raw = db.$withoutPlugins();
    expect((await raw.tags.findMany()).error).toBeNull();
    expect(wrapped).not.toHaveBeenCalled();
    expect(requests).toHaveLength(1);
    expect((await raw.$with({ tenant: 'x' }).tags.findMany()).error).toBeNull();
  });
});
