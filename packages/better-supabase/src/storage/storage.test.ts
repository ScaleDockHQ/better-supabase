import { describe, expect, it } from 'vitest';

import { DbException } from '../core/errors.ts';
import { defineBucket, fromStorageError, parseSize } from './index.ts';

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
      "with check (bucket_id = 'customer-logos' and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'org_id', (select auth.jwt()) -> 'app_metadata' ->> 'org_id')) and name ~ '^[^/]+/[^/]+/logo/[^/]+\\.webp$')",
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
