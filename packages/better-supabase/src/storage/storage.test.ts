import { createClient } from '@supabase/supabase-js';
import { describe, expect, expectTypeOf, it, vi } from 'vitest';

import { DbException } from '../core/errors.ts';
import {
  defineBucket,
  fromStorageError,
  parseSize,
  type StoragePath,
} from './index.ts';

const logos = defineBucket({
  id: 'customer-logos',
  path: '{orgId}/{customerId}/logo/{version}.webp',
  policy: 'tenant',
  fileSizeLimit: '5MiB',
  allowedMimeTypes: ['image/png', 'image/*'],
});

describe('defineBucket', () => {
  it('builds, matches and prefixes paths', () => {
    const path = logos.path({ orgId: 'o1', customerId: 'c1', version: 3 });
    expect(path).toBe('o1/c1/logo/3.webp');
    expect(logos.match(path)).toEqual({
      orgId: 'o1',
      customerId: 'c1',
      version: '3',
    });
    expect(logos.match('o1/c1/logo/3.png')).toBeNull();
    expect(logos.match('o1/c1/extra/logo/3.webp')).toBeNull();
    expect(logos.prefix({ orgId: 'o1' })).toBe('o1');
    expect(logos.prefix({ orgId: 'o1', customerId: 'c1', version: 'x' })).toBe(
      'o1/c1/logo',
    );
    expect(logos.params).toEqual(['orgId', 'customerId', 'version']);
  });

  it('rejects unsafe segment values', () => {
    for (const customerId of ['', '..', 'a/b', 'a\u0000b', 'naïve']) {
      expect(() => logos.path({ orgId: 'o1', customerId, version: 1 })).toThrow(
        DbException,
      );
    }
  });

  it('checks size and type', () => {
    expect(logos.check({ size: 5 * 1024 * 1024 + 1 })).toMatchObject({
      kind: 'invalid_input',
      status: 413,
      message: 'File is larger than 5MiB',
    });
    expect(logos.check({ type: 'text/plain' })).toMatchObject({ status: 415 });
    expect(
      logos.check({ size: 10, type: 'image/webp; charset=binary' }),
    ).toBeUndefined();
  });

  it('generates idempotent SQL with tenant policies', () => {
    const sql = logos.sql();
    expect(sql).toContain(
      "values ('customer-logos', 'customer-logos', false, 5242880, array['image/png', 'image/*'])",
    );
    expect(sql).toContain(
      'drop policy if exists "bs_customer_logos_insert" on storage.objects;',
    );
    expect(sql).toContain(
      "with check (bucket_id = 'customer-logos' and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) and name ~ '^[^/]+/[^/]+/logo/[^/]+\\.webp$')",
    );
    const owner = defineBucket({
      id: 'avatars',
      path: 'users/{userId}/{file}',
      policy: 'owner',
    }).sql();
    expect(owner).toContain(
      "split_part(name, '/', 2) = (select auth.uid())::text",
    );
    const open = defineBucket({
      id: 'public',
      path: '{file}',
      policy: 'public',
      public: true,
    }).sql();
    expect(open).toContain(
      "for select to anon, authenticated\n  using (bucket_id = 'public')",
    );
    expect(open).not.toContain('for insert');
  });

  it('writes config.toml and detects drift', () => {
    expect(logos.toml()).toBe(
      '[storage.buckets.customer-logos]\npublic = false\nfile_size_limit = "5MiB"\nallowed_mime_types = ["image/png", "image/*"]\n',
    );
    expect(
      logos.drift({
        public: false,
        fileSizeLimit: 5_242_880,
        allowedMimeTypes: ['image/*', 'image/png'],
      }),
    ).toEqual([]);
    expect(
      logos
        .drift({ public: true, fileSizeLimit: null, allowedMimeTypes: null })
        .map((drift) => drift.field),
    ).toEqual(['public', 'fileSizeLimit', 'allowedMimeTypes']);
    expect(logos.drift(undefined)[0]?.field).toBe('missing');
  });

  it('compiles PermDock policies with list split from read', () => {
    const files = defineBucket({
      id: 'org-files',
      path: '{orgId}/{file}',
      policy: {
        permdock: {
          read: 'files.read',
          list: 'files.list',
          write: 'files.write',
        },
        scope: 'organization',
      },
    });
    const sql = files.sql();
    const ids = (key: string) =>
      `split_part(name, '/', 1) in (select t.id::text from "public"."permitted_organization_ids"('${key}') as t(id))`;
    const listing =
      "storage.allow_any_operation(array['object.list', 'object.list_v2', 's3.object.list'])";
    expect(sql).toContain(
      `create policy "bs_org_files_select" on storage.objects for select to authenticated\n  using (bucket_id = 'org-files' and not ${listing} and ${ids('files.read')});`,
    );
    expect(sql).toContain(
      `create policy "bs_org_files_list" on storage.objects for select to authenticated\n  using (bucket_id = 'org-files' and ${listing} and ${ids('files.list')});`,
    );
    expect(sql).toContain(
      `with check (bucket_id = 'org-files' and ${ids('files.write')} and name ~`,
    );
    expect(sql).toContain(
      `for delete to authenticated\n  using (bucket_id = 'org-files' and ${ids('files.write')});`,
    );
    expect(sql).not.toMatch(/service_role|anon/);

    const global = defineBucket({
      id: 'docs',
      path: '{file}',
      policy: {
        permdock: {
          read: 'docs.read',
          write: 'docs.write',
          delete: 'docs.delete',
        },
        scope: 'global',
        schema: 'authz',
      },
    }).sql();
    expect(global).toContain(
      `using (bucket_id = 'docs' and (select "authz".permdock_has('docs.read')));`,
    );
    expect(global).toContain(`(select "authz".permdock_has('docs.delete'))`);
    expect(global).toContain('drop policy if exists "bs_docs_list"');
    expect(global).not.toContain('allow_any_operation');
    expect(global).not.toContain('service_role');
  });

  it('refuses PermDock keys it cannot compile', () => {
    const bucket = (
      read: string,
      scope = 'organization',
      path = '{orgId}/{file}',
    ) =>
      defineBucket({
        id: 'x',
        path,
        policy: { permdock: { read, write: 'x.write' }, scope },
      });
    expect(() => bucket('files.read#2')).toThrow(/splits by row condition/);
    expect(() => bucket('')).toThrow(/empty/);
    expect(() => bucket('x.read', 'org; drop')).toThrow(
      /invalid PermDock scope/,
    );
    expect(() => bucket('x.read', 'organization', '{file}')).toThrow(
      /whole path segment/,
    );
  });

  it('rejects policies that cannot be enforced', () => {
    expect(() =>
      defineBucket({ id: 'x', path: 'org-{orgId}/{file}', policy: 'tenant' }),
    ).toThrow(/whole path segment/);
    expect(() =>
      defineBucket({ id: 'x', path: '{a}{b}', policy: 'none' }),
    ).toThrow(/adjacent/);
    expect(() => defineBucket({ id: 'x', path: '/{a}' })).toThrow(
      /empty segment/,
    );
  });
});

describe('storage helpers', () => {
  it('parses sizes', () => {
    expect(parseSize('5MiB')).toBe(5_242_880);
    expect(parseSize('500KB')).toBe(500_000);
    expect(parseSize(12)).toBe(12);
    expect(() => parseSize('lots')).toThrow('Invalid size "lots"');
  });

  it('maps Storage errors', () => {
    expect(
      fromStorageError({
        name: 'StorageApiError',
        message: 'new row violates row-level security policy',
        status: 400,
        statusCode: '403',
      }).kind,
    ).toBe('forbidden');
    expect(
      fromStorageError({
        name: 'StorageApiError',
        message: 'The resource already exists',
        status: 400,
        statusCode: '409',
      }).kind,
    ).toBe('conflict');
    expect(
      fromStorageError({
        name: 'StorageApiError',
        message: 'Object not found',
        status: 400,
        statusCode: '404',
      }).kind,
    ).toBe('not_found');
    expect(
      fromStorageError({
        name: 'StorageApiError',
        message: 'Payload too large',
        status: 413,
        statusCode: '413',
      }),
    ).toMatchObject({ kind: 'invalid_input', status: 413 });
    expect(
      fromStorageError({ name: 'StorageUnknownError', message: 'fetch failed' })
        .kind,
    ).toBe('network');
  });
});

describe('renderUrl', () => {
  const URL_BASE = 'https://abcdefghijklmnopqrst.supabase.co';
  const client = (fetch: typeof globalThis.fetch) =>
    createClient(URL_BASE, 'sb_publishable_test', {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { fetch },
    });
  const transform = {
    width: 320,
    height: 200,
    resize: 'cover',
    quality: 70,
  } as const;

  it('builds a /render/image/public URL for public buckets without a request', async () => {
    const fetch = vi.fn<typeof globalThis.fetch>();
    const avatars = defineBucket({
      id: 'avatars',
      path: '{userId}/{file}',
      public: true,
      policy: 'public',
    }).connect(client(fetch));
    const url = await avatars
      .renderUrl({ userId: 'u1', file: 'me.webp' }, transform)
      .orThrow();
    expect(fetch).not.toHaveBeenCalled();
    const parsed = new URL(url);
    expect(parsed.pathname).toBe(
      '/storage/v1/render/image/public/avatars/u1/me.webp',
    );
    expect(Object.fromEntries(parsed.searchParams)).toEqual({
      width: '320',
      height: '200',
      resize: 'cover',
      quality: '70',
    });
  });

  it('signs a /render/image/sign URL for private buckets', async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json({
        signedURL:
          '/render/image/sign/customer-logos/o1/c1/logo/3.webp?token=t0k',
      }),
    );
    const url = await logos
      .connect(client(fetch))
      .renderUrl('o1/c1/logo/3.webp', transform, { ttl: 'day' })
      .orThrow();
    const [input, init] = fetch.mock.calls[0]!;
    expect(String(input)).toBe(
      `${URL_BASE}/storage/v1/object/sign/customer-logos/o1/c1/logo/3.webp`,
    );
    expect(JSON.parse(String(init?.body))).toEqual({
      expiresIn: 86_400,
      transform,
    });
    expect(url).toBe(
      `${URL_BASE}/storage/v1/render/image/sign/customer-logos/o1/c1/logo/3.webp?token=t0k`,
    );
  });
});

describe('StoragePath', () => {
  it('brands paths with the bucket id', () => {
    const path = logos.path({ orgId: 'o1', customerId: 'c1', version: 1 });
    expectTypeOf(path).toEqualTypeOf<StoragePath<'customer-logos'>>();
    expectTypeOf(path).toExtend<string>();
    const bucket = logos.connect({} as never);
    type Target = Parameters<typeof bucket.exists>[0];
    expectTypeOf(path).toExtend<Target>();
    expectTypeOf('o1/c1/logo/1.webp').toExtend<Target>();
    const avatar = '' as StoragePath<'avatars'>;
    const wrongBucket = () =>
      // @ts-expect-error a path from another bucket
      bucket.exists(avatar);
    expectTypeOf(wrongBucket).toBeFunction();
  });
});
