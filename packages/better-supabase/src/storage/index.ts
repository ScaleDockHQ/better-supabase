import type { SupabaseClient } from '@supabase/supabase-js';

import type {
  BucketPolicyName,
  PermdockBucketPolicy,
} from '../schema/types.ts';
import type { PathIn, StoragePath } from './path.ts';

import { tenantClaimPaths } from '../core/claims.ts';
import {
  type DbError,
  DbException,
  dbError,
  isDbError,
} from '../core/errors.ts';
import { permdockCheck } from '../core/permdock-sql.ts';
import { AsyncResult, err, ok, toDbError } from '../core/result.ts';
import {
  parseTemplate,
  slug,
  sqlIdent,
  sqlString,
  type Template,
  type TemplateParams,
  type TemplateValues,
} from '../core/template.ts';

export type { TemplateParams, TemplateValues } from '../core/template.ts';
export type { PathIn, StoragePath } from './path.ts';

export type { PermdockBucketPolicy } from '../schema/types.ts';

export type BucketPolicy = BucketPolicyName | PermdockBucketPolicy;

/** Storage operations that list objects; every other `select` is a read. */
const LIST_OPERATIONS = ['object.list', 'object.list_v2', 's3.object.list'];

interface PermdockChecks {
  readonly read: string;
  readonly list?: string;
  readonly write: string;
  readonly delete: string;
}

export interface BucketConfig<
  P extends string = string,
  Id extends string = string,
> {
  /** Bucket id, e.g. `customer-logos`. */
  readonly id: Id;
  /** Object path template, e.g. `{orgId}/{customerId}/logo/{version}.webp`. */
  readonly path: P;
  readonly public?: boolean;
  /**
   * Generated `storage.objects` policies. `tenant` and `owner` match a path
   * segment against the JWT; `public` allows reads; `none` leaves access to
   * the secret key; `{ permdock, scope }` calls PermDock's SQL helpers.
   * Defaults to `none`.
   *
   * The helpers check role and scope only. Use `permdock` just for
   * permissions whose grants have no row conditions beyond the scope: for a
   * permission with row conditions (e.g. `ownerId = principal.id`) the bucket
   * grants every object in the scope. Leave those to the policies
   * `permdock rls generate` writes.
   */
  readonly policy?: BucketPolicy;
  /** `'5MiB'`, `'500KB'` or bytes. */
  readonly fileSizeLimit?: string | number;
  /** `['image/png', 'image/*']`. */
  readonly allowedMimeTypes?: readonly string[];
  readonly tenant?: {
    /** Placeholder holding the tenant id. Defaults to `orgId`. */
    readonly param?: string;
    /** JWT claim paths, first match wins. Defaults to `tenant_id`, then `app_metadata.tenant_id`. */
    readonly claim?: string | readonly string[];
    /** SQL expression for the tenant id, instead of `claim`. */
    readonly sql?: string;
  };
  readonly owner?: {
    /** Placeholder holding the user id. Defaults to `userId`. */
    readonly param?: string;
  };
}

/**
 * A path from the template's values, or an existing path string (checked
 * against the template). `StoragePath`s of other buckets are rejected.
 */
export type ObjectTarget<P extends string, Id extends string = string> =
  | TemplateValues<P>
  | PathIn<Id>;

export const TTL = {
  minute: 60,
  hour: 3600,
  day: 86_400,
  week: 604_800,
} as const;
export type TtlPreset = keyof typeof TTL;

export interface TransformOptions {
  readonly width?: number;
  readonly height?: number;
  readonly resize?: 'cover' | 'contain' | 'fill';
  readonly quality?: number;
  readonly format?: 'origin';
}

export type UploadBody =
  | Blob
  | ArrayBuffer
  | ArrayBufferView
  | ReadableStream<Uint8Array>
  | FormData
  | string;

export interface UploadOptions {
  readonly contentType?: string;
  readonly cacheControl?: string;
  readonly upsert?: boolean;
  readonly metadata?: Readonly<Record<string, unknown>>;
  readonly signal?: AbortSignal;
}

export interface UrlOptions {
  /** Seconds or a preset. Defaults to `hour`. */
  readonly ttl?: number | TtlPreset;
  readonly transform?: TransformOptions;
  /** Serve as an attachment, optionally with a file name. */
  readonly download?: boolean | string;
}

export interface StoredObject {
  readonly path: string;
  readonly size?: number;
  readonly contentType?: string;
  readonly createdAt: string | null;
  readonly updatedAt: string | null;
}

export interface Reservation {
  readonly path: string;
  readonly token: string;
  readonly signedUrl: string;
}

export interface ReplaceOptions<
  Id extends string = string,
> extends UploadOptions {
  /** Path the object replaces. Removed after `commit` succeeds. */
  readonly previous?: string | null;
  /**
   * Store the new path, e.g. update the row. Throwing or returning an error
   * `Result` removes the new object and keeps the previous one.
   */
  readonly commit?: (path: StoragePath<Id>) => unknown;
}

export interface ReplaceResult<Id extends string = string> {
  readonly path: StoragePath<Id>;
  readonly removed: string | null;
  /** Set when the previous object could not be removed. */
  readonly cleanup?: DbError;
}

export interface SweepOptions<P extends string> {
  /** Only look under the path prefix these values fill. */
  readonly within?: Partial<TemplateValues<P>>;
  /** Minimum age in milliseconds, or a cutoff date. */
  readonly olderThan: number | Date;
  /** Returns which of `paths` are still referenced. */
  readonly referenced: (
    paths: readonly string[],
  ) => PromiseLike<Iterable<string>> | Iterable<string>;
  readonly dryRun?: boolean;
  readonly batchSize?: number;
  readonly signal?: AbortSignal;
  readonly now?: () => number;
}

export interface SweepResult {
  readonly scanned: number;
  readonly orphans: readonly string[];
  readonly removed: readonly string[];
}

export interface BucketDrift {
  readonly field: 'missing' | 'public' | 'fileSizeLimit' | 'allowedMimeTypes';
  readonly expected: unknown;
  readonly actual: unknown;
  readonly message: string;
}

/** Bucket state as stored in `storage.buckets` (or `better-supabase` introspection). */
export interface ActualBucket {
  readonly public: boolean;
  readonly fileSizeLimit?: number | null;
  readonly allowedMimeTypes?: readonly string[] | null;
}

export type StorageClient = Pick<SupabaseClient, 'storage'>;

export interface BucketClient<P extends string, Id extends string = string> {
  readonly bucket: Bucket<P, Id>;
  upload(
    target: ObjectTarget<P, Id>,
    body: UploadBody,
    options?: UploadOptions,
  ): AsyncResult<{ path: StoragePath<Id> }>;
  download(
    target: ObjectTarget<P, Id>,
    options?: { signal?: AbortSignal },
  ): AsyncResult<Blob>;
  exists(target: ObjectTarget<P, Id>): AsyncResult<boolean>;
  remove(
    targets: readonly ObjectTarget<P, Id>[],
  ): AsyncResult<readonly string[]>;
  list(
    within?: Partial<TemplateValues<P>>,
    options?: { signal?: AbortSignal },
  ): AsyncResult<readonly StoredObject[]>;
  signedUrl(
    target: ObjectTarget<P, Id>,
    options?: UrlOptions,
  ): AsyncResult<string>;
  signedUrls(
    targets: readonly ObjectTarget<P, Id>[],
    options?: Omit<UrlOptions, 'transform'>,
  ): AsyncResult<readonly string[]>;
  /** URL for public buckets. No request is made. */
  publicUrl(
    target: ObjectTarget<P, Id>,
    options?: Omit<UrlOptions, 'ttl'>,
  ): string;
  /** Image transform URL: public for public buckets, signed otherwise. */
  renderUrl(
    target: ObjectTarget<P, Id>,
    transform: TransformOptions,
    options?: Omit<UrlOptions, 'transform'>,
  ): AsyncResult<string>;
  /** Upload the new object, run `commit`, then remove the previous object. */
  replace(
    target: ObjectTarget<P, Id>,
    body: UploadBody,
    options?: ReplaceOptions<Id>,
  ): AsyncResult<ReplaceResult<Id>>;
  /** A signed upload URL for a browser or another service. */
  reserve(
    target: ObjectTarget<P, Id>,
    options?: { upsert?: boolean },
  ): AsyncResult<Reservation>;
  uploadReserved(
    reservation: Pick<Reservation, 'path' | 'token'>,
    body: UploadBody,
    options?: UploadOptions,
  ): AsyncResult<{ path: StoragePath<Id> }>;
  /** Removes objects that match the template, are old enough and are not referenced. */
  sweep(options: SweepOptions<P>): AsyncResult<SweepResult>;
}

export interface Bucket<P extends string, Id extends string = string> {
  readonly id: Id;
  readonly template: P;
  readonly params: readonly TemplateParams<P>[];
  readonly public: boolean;
  readonly policy: BucketPolicy;
  /**
   * Placeholder holding the owning user's id: `owner.param` for `owner`
   * buckets, otherwise `userId` when the template has it. Account deletion
   * removes the objects it fills.
   */
  readonly owner: string | undefined;
  readonly fileSizeLimit: number | undefined;
  readonly allowedMimeTypes: readonly string[] | undefined;
  path(values: TemplateValues<P>): StoragePath<Id>;
  match(path: string): TemplateValues<P> | null;
  /** Folder prefix filled by `values`, for listing. */
  prefix(values?: Partial<TemplateValues<P>>): string;
  /** Checks a size and content type against the bucket limits. */
  check(file: { size?: number; type?: string }): DbError | undefined;
  /** `insert into storage.buckets` plus `storage.objects` policies. Idempotent. */
  sql(): string;
  /** A `[storage.buckets.<id>]` section for `supabase/config.toml`. */
  toml(): string;
  drift(actual: ActualBucket | undefined): readonly BucketDrift[];
  connect(client: StorageClient): BucketClient<P, Id>;
}

const SIZE_UNITS: Readonly<Record<string, number>> = {
  b: 1,
  kb: 1000,
  kib: 1024,
  mb: 1000 ** 2,
  mib: 1024 ** 2,
  gb: 1000 ** 3,
  gib: 1024 ** 3,
};

export function parseSize(value: string | number): number {
  if (typeof value === 'number') return value;
  const match = /^\s*(\d+(?:\.\d+)?)\s*([a-z]*)\s*$/i.exec(value);
  // oxlint-disable-next-line typescript/prefer-nullish-coalescing -- an empty unit means bytes.
  const unit = SIZE_UNITS[(match?.[2] || 'b').toLowerCase()];
  if (!match || unit === undefined)
    throw new TypeError(`Invalid size "${value}"`);
  return Math.round(Number(match[1]) * unit);
}

// Characters Supabase Storage accepts in object keys, minus the separator.
const SAFE_SEGMENT = /^[\w!\-.*'() &$@=;:+,?]+$/;

function validateSegment(_name: string, value: string): string | undefined {
  if (value === '.' || value === '..') return 'is a relative path';
  if (!SAFE_SEGMENT.test(value))
    return 'contains characters Storage does not allow';
  return undefined;
}

function claimSql(claim: string | readonly string[]): string {
  const paths = typeof claim === 'string' ? [claim] : claim;
  const expressions = paths.map((path) => {
    const keys = path.split('.');
    const last = keys.pop()!;
    return `(select auth.jwt())${keys.map((key) => ` -> ${sqlString(key)}`).join('')} ->> ${sqlString(last)}`;
  });
  return expressions.length === 1
    ? expressions[0]!
    : `coalesce(${expressions.join(', ')})`;
}

function mimeAllowed(allowed: readonly string[], type: string): boolean {
  const base = type.split(';')[0]!.trim().toLowerCase();
  return allowed.some((entry) => {
    const pattern = entry.toLowerCase();
    return pattern.endsWith('/*')
      ? base.startsWith(pattern.slice(0, -1))
      : base === pattern;
  });
}

function sizeLabel(bytes: number): string {
  for (const [unit, size] of [
    ['GiB', 1024 ** 3],
    ['MiB', 1024 ** 2],
    ['KiB', 1024],
  ] as const) {
    if (bytes >= size && bytes % size === 0)
      return `${String(bytes / size)}${unit}`;
  }
  return `${String(bytes)}B`;
}

interface StorageFailure {
  readonly message?: string;
  readonly name?: string;
  readonly status?: number;
  readonly statusCode?: string;
  readonly code?: string;
}

/** Maps a Storage error (`StorageApiError`, fetch failures) to a `DbError`. */
export function fromStorageError(raw: unknown, table?: string): DbError {
  if (isDbError(raw)) return raw;
  if (raw instanceof DbException) return raw.error;
  if (typeof raw !== 'object' || raw === null) return toDbError(raw);
  const failure = raw as StorageFailure;
  if (failure.name === 'AbortError') return toDbError(raw);
  const message = failure.message ?? 'Storage request failed';
  const code = failure.code ?? failure.statusCode;
  const base = { ...(code ? { code } : {}), ...(table ? { table } : {}) };
  const statusCode = Number(failure.statusCode);
  const status =
    Number.isFinite(statusCode) && statusCode >= 400
      ? statusCode
      : (failure.status ?? 0);
  if (
    /row-level security|unauthorized to|AccessDenied/i.test(
      `${message} ${code ?? ''}`,
    )
  ) {
    return dbError('forbidden', message, base);
  }
  if (/already exists|duplicate/i.test(`${message} ${code ?? ''}`))
    return dbError('conflict', message, base);
  if (failure.name === 'StorageUnknownError' && status === 0)
    return dbError('network', message, base);
  switch (status) {
    case 400:
      return dbError('invalid_request', message, base);
    case 401:
      return dbError('unauthorized', message, base);
    case 403:
      return dbError('forbidden', message, base);
    case 404:
      return dbError('not_found', message, base);
    case 409:
      return dbError('conflict', message, base);
    case 413:
    case 415:
      return dbError('invalid_input', message, { ...base, status });
    case 408:
    case 429:
      return dbError('network', message, { ...base, status });
    default:
      return status >= 500
        ? dbError('network', message, base)
        : dbError('unexpected', message, base);
  }
}

/**
 * A typed Storage bucket: path builders from a template, limits, generated
 * SQL policies and `config.toml`, and helpers for the multi-step work apps
 * repeat (replace, signed uploads, orphan cleanup).
 *
 * ```ts
 * export const logos = defineBucket({
 *   id: 'customer-logos',
 *   path: '{orgId}/{customerId}/logo/{version}.webp',
 *   policy: 'tenant',
 *   fileSizeLimit: '5MiB',
 *   allowedMimeTypes: ['image/webp'],
 * });
 * ```
 */
export function defineBucket<
  const P extends string,
  const Id extends string = string,
>(config: BucketConfig<P, Id>): Bucket<P, Id> {
  const template: Template = parseTemplate(config.path, '/', validateSegment);
  const policy = config.policy ?? 'none';
  const fileSizeLimit =
    config.fileSizeLimit === undefined
      ? undefined
      : parseSize(config.fileSizeLimit);
  const allowedMimeTypes = config.allowedMimeTypes;

  function segmentFor(param: string, kind: string): number {
    const index = template.segmentOf(param);
    if (index === undefined) {
      throw new TypeError(
        `defineBucket: a ${kind} policy needs {${param}} as a whole path segment in "${config.path}"`,
      );
    }
    return index;
  }
  const mode = typeof policy === 'string' ? policy : 'permdock';
  const accessCheck = ((): string | undefined => {
    switch (mode) {
      case 'tenant': {
        const index = segmentFor(config.tenant?.param ?? 'orgId', 'tenant');
        const expression =
          config.tenant?.sql ??
          claimSql(config.tenant?.claim ?? tenantClaimPaths());
        return `split_part(name, '/', ${String(index)}) = (${expression})`;
      }
      case 'owner': {
        const index = segmentFor(config.owner?.param ?? 'userId', 'owner');
        return `split_part(name, '/', ${String(index)}) = (select auth.uid())::text`;
      }
      case 'public':
      case 'none':
      case 'permdock':
        return undefined;
      default: {
        const unknown: never = mode;
        throw new TypeError(
          `defineBucket: unknown policy "${String(unknown)}"`,
        );
      }
    }
  })();
  const permdock = ((): PermdockChecks | undefined => {
    if (typeof policy === 'string') return undefined;
    const where = `defineBucket(${config.id})`;
    const id =
      policy.scope === 'global'
        ? undefined
        : `split_part(name, '/', ${String(policy.segment ?? segmentFor(config.tenant?.param ?? 'orgId', 'PermDock'))})`;
    const check = (key: string) => permdockCheck(where, policy, key, id);
    const keys = policy.permdock;
    return {
      read: check(keys.read),
      ...(keys.list === undefined ? {} : { list: check(keys.list) }),
      write: check(keys.write),
      delete: check(keys.delete ?? keys.write),
    };
  })();

  const resolve = (target: ObjectTarget<P, Id>): StoragePath<Id> => {
    if (typeof target !== 'string')
      return template.build(target) as StoragePath<Id>;
    if (!template.match(target)) {
      throw new DbException(
        dbError(
          'invalid_input',
          `Path "${target}" does not match "${config.path}"`,
        ),
      );
    }
    return target as StoragePath<Id>;
  };

  const check = (file: {
    size?: number;
    type?: string;
  }): DbError | undefined => {
    if (
      fileSizeLimit !== undefined &&
      file.size !== undefined &&
      file.size > fileSizeLimit
    ) {
      return dbError(
        'invalid_input',
        `File is larger than ${sizeLabel(fileSizeLimit)}`,
        { status: 413 },
      );
    }
    if (
      allowedMimeTypes &&
      file.type &&
      !mimeAllowed(allowedMimeTypes, file.type)
    ) {
      return dbError('invalid_input', `File type ${file.type} is not allowed`, {
        status: 415,
      });
    }
    return undefined;
  };

  const bucket: Bucket<P, Id> = {
    id: config.id,
    template: config.path,
    params: template.params as TemplateParams<P>[],
    owner:
      policy === 'owner'
        ? (config.owner?.param ?? 'userId')
        : template.params.includes('userId')
          ? 'userId'
          : undefined,
    public: config.public ?? false,
    policy,
    fileSizeLimit,
    allowedMimeTypes,
    path: (values) => template.build(values) as StoragePath<Id>,
    match: (path) => template.match(path) as TemplateValues<P> | null,
    prefix: (values = {}) => template.prefix(values, template.segments - 1),
    check,
    sql() {
      const id = sqlString(config.id);
      const name = slug(config.id);
      const lines = [
        `-- better-supabase: bucket ${config.id} (${config.path})`,
        'insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)',
        `values (${id}, ${id}, ${String(bucket.public)}, ${fileSizeLimit === undefined ? 'null' : String(fileSizeLimit)}, ${
          allowedMimeTypes
            ? `array[${allowedMimeTypes.map(sqlString).join(', ')}]`
            : 'null'
        })`,
        'on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,',
        '  allowed_mime_types = excluded.allowed_mime_types;',
      ];
      const policies: [
        string,
        string,
        string,
        string | undefined,
        string | undefined,
      ][] = [];
      const inBucket = `bucket_id = ${id}`;
      const shape = `name ~ ${sqlString(template.sqlPattern)}`;
      if (accessCheck) {
        const using = `${inBucket} and ${accessCheck}`;
        const write = `${using} and ${shape}`;
        policies.push(
          ['select', 'select', 'authenticated', using, undefined],
          ['insert', 'insert', 'authenticated', undefined, write],
          ['update', 'update', 'authenticated', using, write],
          ['delete', 'delete', 'authenticated', using, undefined],
        );
      } else if (policy === 'public') {
        policies.push([
          'select',
          'select',
          'anon, authenticated',
          inBucket,
          undefined,
        ]);
      } else if (permdock) {
        const listing = `storage.allow_any_operation(array[${LIST_OPERATIONS.map(sqlString).join(', ')}])`;
        if (permdock.list) {
          policies.push(
            [
              'select',
              'select',
              'authenticated',
              `${inBucket} and not ${listing} and ${permdock.read}`,
              undefined,
            ],
            [
              'list',
              'select',
              'authenticated',
              `${inBucket} and ${listing} and ${permdock.list}`,
              undefined,
            ],
          );
        } else {
          policies.push([
            'select',
            'select',
            'authenticated',
            `${inBucket} and ${permdock.read}`,
            undefined,
          ]);
        }
        const write = `${inBucket} and ${permdock.write}`;
        policies.push(
          [
            'insert',
            'insert',
            'authenticated',
            undefined,
            `${write} and ${shape}`,
          ],
          ['update', 'update', 'authenticated', write, `${write} and ${shape}`],
          [
            'delete',
            'delete',
            'authenticated',
            `${inBucket} and ${permdock.delete}`,
            undefined,
          ],
        );
      }
      for (const [suffix, command, roles, using, withCheck] of policies) {
        const policyName = sqlIdent(`bs_${name}_${suffix}`);
        lines.push(
          '',
          `drop policy if exists ${policyName} on storage.objects;`,
          `create policy ${policyName} on storage.objects for ${command} to ${roles}${
            using ? `\n  using (${using})` : ''
          }${withCheck ? `\n  with check (${withCheck})` : ''};`,
        );
      }
      if (permdock && !permdock.list) {
        lines.push(
          '',
          `drop policy if exists ${sqlIdent(`bs_${name}_list`)} on storage.objects;`,
        );
      }
      return `${lines.join('\n')}\n`;
    },
    toml() {
      const lines = [
        `[storage.buckets.${config.id}]`,
        `public = ${String(bucket.public)}`,
      ];
      if (config.fileSizeLimit !== undefined) {
        lines.push(
          `file_size_limit = "${typeof config.fileSizeLimit === 'number' ? sizeLabel(config.fileSizeLimit) : config.fileSizeLimit}"`,
        );
      }
      if (allowedMimeTypes)
        lines.push(
          `allowed_mime_types = [${allowedMimeTypes.map((type) => JSON.stringify(type)).join(', ')}]`,
        );
      return `${lines.join('\n')}\n`;
    },
    drift(actual) {
      if (!actual) {
        return [
          {
            field: 'missing',
            expected: config.id,
            actual: undefined,
            message: `Bucket "${config.id}" does not exist`,
          },
        ];
      }
      const issues: BucketDrift[] = [];
      if (actual.public !== bucket.public) {
        issues.push({
          field: 'public',
          expected: bucket.public,
          actual: actual.public,
          message: `Bucket "${config.id}" public is ${String(actual.public)}`,
        });
      }
      if ((actual.fileSizeLimit ?? undefined) !== fileSizeLimit) {
        issues.push({
          field: 'fileSizeLimit',
          expected: fileSizeLimit,
          actual: actual.fileSizeLimit,
          message: `Bucket "${config.id}" file size limit differs`,
        });
      }
      const sorted = (list: readonly string[] | null | undefined) =>
        list ? [...list].sort().join(',') : '';
      if (sorted(actual.allowedMimeTypes) !== sorted(allowedMimeTypes)) {
        issues.push({
          field: 'allowedMimeTypes',
          expected: allowedMimeTypes,
          actual: actual.allowedMimeTypes,
          message: `Bucket "${config.id}" allowed MIME types differ`,
        });
      }
      return issues;
    },
    connect: (client) => connectBucket(bucket, client, resolve),
  };
  return bucket;
}

function bodyInfo(
  body: UploadBody,
  contentType: string | undefined,
): { size?: number; type?: string } {
  const info: { size?: number; type?: string } = {};
  if (typeof Blob !== 'undefined' && body instanceof Blob) {
    info.size = body.size;
    if (body.type) info.type = body.type;
  } else if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) {
    info.size = body.byteLength;
  }
  if (contentType) info.type = contentType;
  return info;
}

function ttlSeconds(ttl: number | TtlPreset | undefined): number {
  return typeof ttl === 'number' ? ttl : TTL[ttl ?? 'hour'];
}

function isErrorResult(value: unknown): value is { ok: false; error: DbError } {
  return (
    typeof value === 'object' &&
    value !== null &&
    (value as { ok?: unknown }).ok === false &&
    'error' in value
  );
}

function connectBucket<P extends string, Id extends string>(
  bucket: Bucket<P, Id>,
  client: StorageClient,
  resolve: (target: ObjectTarget<P, Id>) => StoragePath<Id>,
): BucketClient<P, Id> {
  const api = () => client.storage.from(bucket.id);
  const run = <T>(
    fn: () => PromiseLike<{ data: T; error: unknown }>,
  ): AsyncResult<NonNullable<T>> =>
    AsyncResult.from(async () => {
      try {
        const { data, error } = await fn();
        return error || data === null
          ? err(fromStorageError(error, bucket.id))
          : ok(data as NonNullable<T>);
      } catch (cause) {
        return err(fromStorageError(cause, bucket.id));
      }
    });
  const fileOptions = (
    options: UploadOptions | undefined,
    contentType: string | undefined,
  ) => ({
    ...(contentType ? { contentType } : {}),
    ...(options?.cacheControl ? { cacheControl: options.cacheControl } : {}),
    ...(options?.metadata ? { metadata: { ...options.metadata } } : {}),
    upsert: options?.upsert ?? false,
  });
  const download = (value: boolean | string | undefined) =>
    value === undefined ? {} : { download: value };

  const upload: BucketClient<P, Id>['upload'] = (target, body, options) =>
    AsyncResult.from(async () => {
      options?.signal?.throwIfAborted();
      const path = resolve(target);
      const contentType = options?.contentType;
      const problem = bucket.check(bodyInfo(body, contentType));
      if (problem) return err(problem);
      return run(() =>
        api().upload(path, body, fileOptions(options, contentType)),
      ).map(() => ({ path }));
    });

  const remove: BucketClient<P, Id>['remove'] = (targets) =>
    AsyncResult.from(async () => {
      const paths = targets.map(resolve);
      if (paths.length === 0) return ok([]);
      return run(() => api().remove(paths)).map(() => paths);
    });

  const walk = async (
    folder: string,
    signal: AbortSignal | undefined,
    out: StoredObject[],
  ) => {
    const limit = 1000;
    for (let offset = 0; ; offset += limit) {
      signal?.throwIfAborted();
      const { data, error } = await api().list(
        folder,
        { limit, offset, sortBy: { column: 'name', order: 'asc' } },
        signal ? { signal } : {},
      );
      if (error) throw new DbException(fromStorageError(error, bucket.id));
      for (const item of data) {
        const path = folder ? `${folder}/${item.name}` : item.name;
        if (item.id === null) await walk(path, signal, out);
        else {
          const metadata = (item.metadata ?? {}) as {
            size?: number;
            mimetype?: string;
          };
          out.push({
            path,
            ...(typeof metadata.size === 'number'
              ? { size: metadata.size }
              : {}),
            ...(metadata.mimetype ? { contentType: metadata.mimetype } : {}),
            createdAt: item.created_at,
            updatedAt: item.updated_at,
          });
        }
      }
      if (data.length < limit) return;
    }
  };

  const list: BucketClient<P, Id>['list'] = (within, options) =>
    AsyncResult.from(async () => {
      const out: StoredObject[] = [];
      await walk(bucket.prefix(within ?? {}), options?.signal, out);
      return ok(out);
    }).mapError((error) => ({ ...error, table: bucket.id }));

  const signedUrl: BucketClient<P, Id>['signedUrl'] = (target, options) =>
    AsyncResult.from(async () => {
      const path = resolve(target);
      return run(() =>
        api().createSignedUrl(path, ttlSeconds(options?.ttl), {
          ...download(options?.download),
          ...(options?.transform
            ? { transform: { ...options.transform } }
            : {}),
        }),
      ).map((data) => data.signedUrl);
    });

  return {
    bucket,
    upload,
    download: (target, options) =>
      AsyncResult.from(async () => {
        const path = resolve(target);
        return run(() =>
          api().download(
            path,
            {},
            options?.signal ? { signal: options.signal } : {},
          ),
        );
      }),
    exists: (target) =>
      AsyncResult.from(async () => {
        const path = resolve(target);
        const found = await api().exists(path);
        if (!found.data) return ok(false);
        return found.error
          ? err(fromStorageError(found.error, bucket.id))
          : ok(true);
      }),
    remove,
    list,
    signedUrl,
    signedUrls: (targets, options) =>
      AsyncResult.from(async () => {
        const paths = targets.map(resolve);
        if (paths.length === 0) return ok([]);
        return run(() =>
          api().createSignedUrls(
            paths,
            ttlSeconds(options?.ttl),
            download(options?.download),
          ),
        ).andThen(async (data) => {
          const failed = data.find(
            (entry) => entry.error != null || !entry.signedUrl,
          );
          if (failed)
            return err(
              dbError(
                'not_found',
                failed.error ?? `No URL for ${String(failed.path)}`,
                { table: bucket.id },
              ),
            );
          return ok(data.map((entry) => entry.signedUrl as string));
        });
      }),
    publicUrl(target, options) {
      const path = resolve(target);
      return api().getPublicUrl(path, {
        ...download(options?.download),
        ...(options?.transform ? { transform: { ...options.transform } } : {}),
      }).data.publicUrl;
    },
    renderUrl(target, transform, options) {
      if (!bucket.public) return signedUrl(target, { ...options, transform });
      return AsyncResult.from(async () =>
        ok(
          api().getPublicUrl(resolve(target), {
            ...download(options?.download),
            transform: { ...transform },
          }).data.publicUrl,
        ),
      );
    },
    replace: (target, body, options = {}) =>
      AsyncResult.from<ReplaceResult<Id>>(async () => {
        const path = resolve(target);
        const previous = options.previous ?? null;
        const same = previous === path;
        const uploaded = await upload(path, body, {
          ...options,
          upsert: same || (options.upsert ?? false),
        });
        if (!uploaded.ok) return uploaded;
        const undo = async (error: DbError) => {
          if (!same) await remove([path]);
          return err(error);
        };
        try {
          options.signal?.throwIfAborted();
          const outcome: unknown = await options.commit?.(path);
          if (isErrorResult(outcome)) return await undo(outcome.error);
        } catch (cause) {
          return undo(fromStorageError(cause, bucket.id));
        }
        if (!previous || same) return ok({ path, removed: null });
        const removed = await run(() => api().remove([previous]));
        return ok(
          removed.ok
            ? { path, removed: previous }
            : { path, removed: null, cleanup: removed.error },
        );
      }),
    reserve: (target, options) =>
      AsyncResult.from(async () => {
        const path = resolve(target);
        return run(() =>
          api().createSignedUploadUrl(
            path,
            options?.upsert ? { upsert: true } : undefined,
          ),
        ).map((data) => ({
          path: data.path,
          token: data.token,
          signedUrl: data.signedUrl,
        }));
      }),
    uploadReserved: (reservation, body, options) =>
      AsyncResult.from(async () => {
        options?.signal?.throwIfAborted();
        const path = resolve(reservation.path);
        const problem = bucket.check(bodyInfo(body, options?.contentType));
        if (problem) return err(problem);
        return run(() =>
          api().uploadToSignedUrl(
            path,
            reservation.token,
            body,
            fileOptions(options, options?.contentType),
          ),
        ).map(() => ({ path }));
      }),
    sweep: (options) =>
      AsyncResult.from(async () => {
        const now = options.now?.() ?? Date.now();
        const cutoff =
          options.olderThan instanceof Date
            ? options.olderThan.getTime()
            : now - options.olderThan;
        const found = await list(
          options.within,
          options.signal ? { signal: options.signal } : undefined,
        );
        if (!found.ok) return found;
        const candidates = found.data
          .filter((object) => bucket.match(object.path) !== null)
          .filter((object) => {
            const created = Date.parse(
              object.createdAt ?? object.updatedAt ?? '',
            );
            return Number.isFinite(created) && created < cutoff;
          })
          .map((object) => object.path);
        const size = options.batchSize ?? 100;
        const orphans: string[] = [];
        const removed: string[] = [];
        for (let index = 0; index < candidates.length; index += size) {
          options.signal?.throwIfAborted();
          const batch = candidates.slice(index, index + size);
          const keep = new Set(await options.referenced(batch));
          const unreferenced = batch.filter((path) => !keep.has(path));
          orphans.push(...unreferenced);
          if (options.dryRun || unreferenced.length === 0) continue;
          const result = await run(() => api().remove(unreferenced));
          if (!result.ok) return result;
          removed.push(...unreferenced);
        }
        return ok({ scanned: found.data.length, orphans, removed });
      }),
  };
}
