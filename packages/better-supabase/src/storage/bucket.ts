import type { SupabaseClient } from "@supabase/supabase-js";

import type { PermdockCatalog } from "../core/permdock-sql.ts";
import type { RequestContext } from "../core/plugin.ts";
import type {
  AccessBucketPolicy,
  BucketPolicyName,
  PermdockBucketPolicy,
} from "../schema/types.ts";
import type { PathIn, StoragePath } from "./path.ts";

import { tenantClaimPaths } from "../core/claims.ts";
import { type DbError, DbException, dbError } from "../core/errors.ts";
import {
  AsyncResult,
  err,
  ok,
  type Result,
  toDbError,
} from "../core/result.ts";
import {
  slug,
  sqlIdent,
  sqlString,
  type TemplateParams,
  type TemplateValues,
} from "../core/template.ts";
import { temporalMissing } from "../core/temporal-required.ts";
import { optionalTemporal } from "../core/temporal.ts";
import { fromStorageError } from "./errors.ts";
import { inScope, pathLayouts } from "./layouts.ts";
import { policyChecks } from "./policy.ts";
import { type TenantGuard, tenantGuard } from "./tenant-scope.ts";

export type BucketPolicy =
  | BucketPolicyName
  | PermdockBucketPolicy
  | AccessBucketPolicy;

/** Storage operations that list objects; every other `select` is a read. */
const LIST_OPERATIONS = ["object.list", "object.list_v2", "s3.object.list"];

export interface BucketConfig<
  P extends string = string,
  Id extends string = string,
> {
  /** Bucket id, e.g. `customer-logos`. */
  readonly id: Id;
  /**
   * Object path template, e.g. `{orgId}/{customerId}/logo/{version}.webp`,
   * or several for a bucket that stores objects in more than one layout. A
   * path from values uses the template whose placeholders are exactly the
   * values given, and a stored path string is accepted when any template
   * matches it, so list the current layout first and keep older ones after
   * it. A last segment `{...rest}` matches one or more segments.
   */
  readonly path: P | readonly [P, ...P[]];
  readonly public?: boolean;
  /**
   * Generated `storage.objects` policies. `tenant` and `owner` match a path
   * segment against the JWT; `public` allows reads (on a `public: true`
   * bucket the public URLs need no policy, so none is written and nobody can
   * list the objects); `none` leaves access to
   * the secret key; `{ permdock, scope }` calls PermDock's SQL helpers;
   * `{ access }` calls the SQL kit's access contract (`tenant_ids_with`).
   * Defaults to `none`.
   *
   * The helpers check role and scope only. Use `permdock` just for
   * permissions whose grants have no row conditions beyond the scope: for a
   * permission with row conditions (e.g. `ownerId = principal.id`) the bucket
   * would grant every object in the scope. Pass `catalog` to refuse those
   * keys here; `better-supabase doctor` (BS214) refuses them from the
   * catalog file.
   */
  readonly policy?: BucketPolicy;
  /**
   * PermDock's `permissions.catalog.json`. With it, a `permdock` policy
   * naming a permission without `rowConditions: false` (including one the
   * catalog doesn't list) throws.
   */
  readonly catalog?: PermdockCatalog;
  /** `'5MiB'`, `'500KB'` or bytes. */
  readonly fileSizeLimit?: string | number;
  /** `['image/png', 'image/*']`. */
  readonly allowedMimeTypes?: readonly string[];
  /**
   * The tenant segment. Set it and connected clients only touch paths whose
   * `param` holds the caller's tenant: pass `{ context }` or `{ tenant }` to
   * `connect()`, or `{ allTenants: true }` for cross-tenant admin work.
   */
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

/** The values of one of the bucket's path templates. */
export type PathValues<P extends string> = P extends string
  ? TemplateValues<P>
  : never;

/**
 * A path from the values of one of the bucket's templates, or an existing
 * path string (checked against the templates). `StoragePath`s of other
 * buckets are rejected.
 */
export type ObjectTarget<P extends string, Id extends string = string> =
  | PathValues<P>
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
  readonly resize?: "cover" | "contain" | "fill";
  readonly quality?: number;
  readonly format?: "origin";
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
  /**
   * Path the object replaces, checked like any other target before the
   * upload. Removed after `commit` succeeds.
   */
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
  /**
   * A cutoff instant, or a minimum age. A duration counts a day as 24 hours
   * and cannot use months or years.
   */
  readonly olderThan: Temporal.Instant | Temporal.Duration;
  /** Returns which of `paths` are still referenced. */
  readonly referenced: (
    paths: readonly string[],
  ) => PromiseLike<Iterable<string>> | Iterable<string>;
  readonly dryRun?: boolean;
  readonly batchSize?: number;
  readonly signal?: AbortSignal;
  readonly now?: () => Temporal.Instant;
}

export interface SweepResult {
  readonly scanned: number;
  readonly orphans: readonly string[];
  readonly removed: readonly string[];
}

export interface BucketDrift {
  readonly field: "missing" | "public" | "fileSizeLimit" | "allowedMimeTypes";
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

export type StorageClient = Pick<SupabaseClient, "storage">;

export interface BucketClient<P extends string, Id extends string = string> {
  readonly bucket: Bucket<P, Id>;
  /** The object path, checked against the template and, with `tenant`, the caller's tenant. */
  path(target: ObjectTarget<P, Id>): Result<StoragePath<Id>>;
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
  /** Copies an object to another path in the bucket; an existing object there is a `conflict`. */
  copy(
    from: ObjectTarget<P, Id>,
    to: ObjectTarget<P, Id>,
  ): AsyncResult<{ path: StoragePath<Id> }>;
  /** Moves an object to another path in the bucket, as one Storage request. */
  move(
    from: ObjectTarget<P, Id>,
    to: ObjectTarget<P, Id>,
  ): AsyncResult<{ path: StoragePath<Id> }>;
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
    options?: Omit<UrlOptions, "transform">,
  ): AsyncResult<readonly string[]>;
  /**
   * URL for public buckets. No request is made, so it returns a `Result`
   * like `path()`: an error for a path outside the templates or the tenant.
   */
  publicUrl(
    target: ObjectTarget<P, Id>,
    options?: Omit<UrlOptions, "ttl">,
  ): Result<string>;
  /** Image transform URL: public for public buckets, signed otherwise. */
  renderUrl(
    target: ObjectTarget<P, Id>,
    transform: TransformOptions,
    options?: Omit<UrlOptions, "transform">,
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
    reservation: Pick<Reservation, "path" | "token">,
    body: UploadBody,
    options?: UploadOptions,
  ): AsyncResult<{ path: StoragePath<Id> }>;
  /** Removes objects that match a template and the `within` values, are old enough and are not referenced. */
  sweep(options: SweepOptions<P>): AsyncResult<SweepResult>;
}

export interface Bucket<P extends string, Id extends string = string> {
  readonly id: Id;
  /** The first path template. */
  readonly template: P;
  /** Every path template, in the order given. */
  readonly templates: readonly P[];
  readonly params: readonly TemplateParams<P>[];
  readonly public: boolean;
  readonly policy: BucketPolicy;
  /**
   * Placeholder holding the owning user's id: `owner.param` for `owner`
   * buckets, otherwise `userId` when the template has it. Account deletion
   * removes the objects it fills.
   */
  readonly owner: string | undefined;
  /** Placeholder connected clients check against the caller's tenant; set by `tenant`. */
  readonly tenant: string | undefined;
  readonly fileSizeLimit: number | undefined;
  readonly allowedMimeTypes: readonly string[] | undefined;
  /** Builds a path with the template whose placeholders are exactly the keys of `values`. */
  path(values: PathValues<P>): StoragePath<Id>;
  /** The values of the first template that matches `path`, or `null`. */
  match(path: string): PathValues<P> | null;
  /** Folder prefix filled by `values`, for listing. */
  prefix(values?: Partial<TemplateValues<P>>): string;
  /** Checks a size and content type against the bucket limits. */
  check(file: { size?: number; type?: string }): DbError | undefined;
  /** `insert into storage.buckets` plus `storage.objects` policies. Idempotent. */
  sql(): string;
  /** A `[storage.buckets.<id>]` section for `supabase/config.toml`. */
  toml(): string;
  drift(actual: ActualBucket | undefined): readonly BucketDrift[];
  connect(
    client: StorageClient,
    options?: BucketConnectOptions,
  ): BucketClient<P, Id>;
}

export interface BucketConnectOptions {
  /**
   * Reuse a signed URL for the same path, `ttl`, `transform` and `download`
   * until shortly before it expires (a tenth of the `ttl`, at most a minute).
   * The cache belongs to this connection; connect once per request so URLs
   * never cross users.
   */
  readonly cacheSignedUrls?: boolean;
  /**
   * The request context (`db.$context`, or what an adapter passes to
   * `connect`). For a bucket with `tenant`, its tenant (`context.tenant`, the
   * one `tenant()` resolved, or the `tenant.claim` claims) must fill the
   * tenant segment of every path.
   */
  readonly context?: RequestContext;
  /** The tenant every path must hold, instead of reading it from `context`. */
  readonly tenant?: string;
  /** Skip the tenant check, for admin jobs that work across tenants. */
  readonly allTenants?: boolean;
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
  if (typeof value === "number") return value;
  const match = /^\s*(\d+(?:\.\d+)?)\s*([a-z]*)\s*$/i.exec(value);
  // oxlint-disable-next-line typescript/prefer-nullish-coalescing -- an empty unit means bytes.
  const unit = SIZE_UNITS[(match?.[2] || "b").toLowerCase()];
  if (!match || unit === undefined)
    throw new TypeError(`Invalid size "${value}"`);
  return Math.round(Number(match[1]) * unit);
}

function claimSql(claim: string | readonly string[]): string {
  const paths = typeof claim === "string" ? [claim] : claim;
  const expressions = paths.map((path) => {
    const keys = path.split(".");
    const last = keys.pop()!;
    return `(select auth.jwt())${keys.map((key) => ` -> ${sqlString(key)}`).join("")} ->> ${sqlString(last)}`;
  });
  return expressions.length === 1
    ? expressions[0]!
    : `coalesce(${expressions.join(", ")})`;
}

function mimeAllowed(allowed: readonly string[], type: string): boolean {
  const base = type.split(";")[0]!.trim().toLowerCase();
  return allowed.some((entry) => {
    const pattern = entry.toLowerCase();
    return pattern.endsWith("/*")
      ? base.startsWith(pattern.slice(0, -1))
      : base === pattern;
  });
}

function sizeLabel(bytes: number): string {
  for (const [unit, size] of [
    ["GiB", 1024 ** 3],
    ["MiB", 1024 ** 2],
    ["KiB", 1024],
  ] as const) {
    if (bytes >= size && bytes % size === 0)
      return `${String(bytes / size)}${unit}`;
  }
  return `${String(bytes)}B`;
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
  const layouts = pathLayouts(config.id, config.path, sqlString);
  const policy = config.policy ?? "none";
  const fileSizeLimit =
    config.fileSizeLimit === undefined
      ? undefined
      : parseSize(config.fileSizeLimit);
  const allowedMimeTypes = config.allowedMimeTypes;
  const segmentFor = (param: string, kind: string): number =>
    layouts.segmentOf(param, kind);
  const tenantParam = config.tenant
    ? (config.tenant.param ?? "orgId")
    : undefined;
  if (tenantParam !== undefined)
    layouts.requireParam(tenantParam, "tenant.param");
  const tenantClaim = config.tenant?.claim;
  const mode =
    typeof policy === "string"
      ? policy
      : "permdock" in policy
        ? "permdock"
        : "access";
  const accessCheck = ((): string | undefined => {
    switch (mode) {
      case "tenant": {
        const index = segmentFor(config.tenant?.param ?? "orgId", "tenant");
        const expression =
          config.tenant?.sql ??
          claimSql(config.tenant?.claim ?? tenantClaimPaths());
        return `split_part(name, '/', ${String(index)}) = (${expression})`;
      }
      case "owner": {
        const index = segmentFor(config.owner?.param ?? "userId", "owner");
        return `split_part(name, '/', ${String(index)}) = (select auth.uid())::text`;
      }
      case "public":
      case "none":
      case "permdock":
      case "access":
        return undefined;
      default: {
        const unknown: never = mode;
        throw new TypeError(
          `defineBucket: unknown policy "${String(unknown)}"`,
        );
      }
    }
  })();
  const permdock = policyChecks(config, policy, (kind) =>
    segmentFor(config.tenant?.param ?? "orgId", kind),
  );

  const resolve = (target: ObjectTarget<P, Id>): StoragePath<Id> => {
    if (typeof target !== "string")
      // SAFETY: a template builds the path from typed values, so it matches
      // the bucket's paths.
      return layouts.build(target) as StoragePath<Id>;
    if (!layouts.match(target)) {
      throw new DbException(
        dbError(
          "invalid_input",
          `Path "${target}" does not match "${layouts.sources.join('" or "')}"`,
        ),
      );
    }
    // SAFETY: template.match accepted the path above.
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
        "invalid_input",
        `File is larger than ${sizeLabel(fileSizeLimit)}`,
        { status: 413 },
      );
    }
    if (
      allowedMimeTypes &&
      file.type &&
      !mimeAllowed(allowedMimeTypes, file.type)
    ) {
      return dbError("invalid_input", `File type ${file.type} is not allowed`, {
        status: 415,
      });
    }
    return undefined;
  };

  // SAFETY: the template parser returns the parameter names written in P,
  // and sources holds the templates of P.
  const bucket: Bucket<P, Id> = {
    id: config.id,
    template: layouts.sources[0] as P,
    templates: layouts.sources as readonly P[],
    params: layouts.params as TemplateParams<P>[],
    owner:
      policy === "owner"
        ? (config.owner?.param ?? "userId")
        : layouts.params.includes("userId")
          ? "userId"
          : undefined,
    tenant: tenantParam,
    public: config.public ?? false,
    policy,
    fileSizeLimit,
    allowedMimeTypes,
    // SAFETY: the template builds the path from typed values, and match returns
    // the parameters of P.
    path: (values) => layouts.build(values) as StoragePath<Id>,
    match: (path) => layouts.match(path) as PathValues<P> | null,
    prefix: (values = {}) => layouts.prefix(values),
    check,
    sql() {
      const id = sqlString(config.id);
      const name = slug(config.id);
      const lines = [
        `-- better-supabase: bucket ${config.id} (${layouts.sources.join(", ")})`,
        "insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)",
        `values (${id}, ${id}, ${String(bucket.public)}, ${fileSizeLimit === undefined ? "null" : String(fileSizeLimit)}, ${
          allowedMimeTypes
            ? `array[${allowedMimeTypes.map(sqlString).join(", ")}]`
            : "null"
        })`,
        "on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,",
        "  allowed_mime_types = excluded.allowed_mime_types;",
      ];
      const policies: [
        string,
        string,
        string,
        string | undefined,
        string | undefined,
      ][] = [];
      const inBucket = `bucket_id = ${id}`;
      const pathMatch = layouts.sqlMatch;
      if (accessCheck) {
        const using = `${inBucket} and ${accessCheck}`;
        const write = `${using} and ${pathMatch}`;
        policies.push(
          ["select", "select", "authenticated", using, undefined],
          ["insert", "insert", "authenticated", undefined, write],
          ["update", "update", "authenticated", using, write],
          ["delete", "delete", "authenticated", using, undefined],
        );
      } else if (policy === "public" && bucket.public) {
        lines.push(
          "-- Public URLs serve objects without a policy; a select policy would also let anyone list them.",
        );
      } else if (policy === "public") {
        policies.push([
          "select",
          "select",
          "anon, authenticated",
          inBucket,
          undefined,
        ]);
      } else if (permdock) {
        const listing = `storage.allow_any_operation(array[${LIST_OPERATIONS.map(sqlString).join(", ")}])`;
        if (permdock.list) {
          policies.push(
            [
              "select",
              "select",
              "authenticated",
              `${inBucket} and not ${listing} and ${permdock.read}`,
              undefined,
            ],
            [
              "list",
              "select",
              "authenticated",
              `${inBucket} and ${listing} and ${permdock.list}`,
              undefined,
            ],
          );
        } else {
          policies.push([
            "select",
            "select",
            "authenticated",
            `${inBucket} and ${permdock.read}`,
            undefined,
          ]);
        }
        const write = `${inBucket} and ${permdock.write}`;
        policies.push(
          [
            "insert",
            "insert",
            "authenticated",
            undefined,
            `${write} and ${pathMatch}`,
          ],
          [
            "update",
            "update",
            "authenticated",
            write,
            `${write} and ${pathMatch}`,
          ],
          [
            "delete",
            "delete",
            "authenticated",
            `${inBucket} and ${permdock.delete}`,
            undefined,
          ],
        );
      }
      for (const [suffix, command, roles, using, withCheck] of policies) {
        const policyName = sqlIdent(`bs_${name}_${suffix}`);
        lines.push(
          "",
          `drop policy if exists ${policyName} on storage.objects;`,
          `create policy ${policyName} on storage.objects for ${command} to ${roles}${
            using ? `\n  using (${using})` : ""
          }${withCheck ? `\n  with check (${withCheck})` : ""};`,
        );
      }
      if (permdock && !permdock.list) {
        lines.push(
          "",
          `drop policy if exists ${sqlIdent(`bs_${name}_list`)} on storage.objects;`,
        );
      }
      return `${lines.join("\n")}\n`;
    },
    toml() {
      const lines = [
        `[storage.buckets.${config.id}]`,
        `public = ${String(bucket.public)}`,
      ];
      if (config.fileSizeLimit !== undefined) {
        lines.push(
          `file_size_limit = "${typeof config.fileSizeLimit === "number" ? sizeLabel(config.fileSizeLimit) : config.fileSizeLimit}"`,
        );
      }
      if (allowedMimeTypes)
        lines.push(
          `allowed_mime_types = [${allowedMimeTypes.map((type) => JSON.stringify(type)).join(", ")}]`,
        );
      return `${lines.join("\n")}\n`;
    },
    drift(actual) {
      if (!actual) {
        return [
          {
            field: "missing",
            expected: config.id,
            actual: undefined,
            message: `Bucket "${config.id}" does not exist`,
          },
        ];
      }
      const issues: BucketDrift[] = [];
      if (actual.public !== bucket.public) {
        issues.push({
          field: "public",
          expected: bucket.public,
          actual: actual.public,
          message: `Bucket "${config.id}" public is ${String(actual.public)}`,
        });
      }
      if ((actual.fileSizeLimit ?? undefined) !== fileSizeLimit) {
        issues.push({
          field: "fileSizeLimit",
          expected: fileSizeLimit,
          actual: actual.fileSizeLimit,
          message: `Bucket "${config.id}" file size limit differs`,
        });
      }
      const sorted = (list: readonly string[] | null | undefined) =>
        list ? [...list].sort().join(",") : "";
      if (sorted(actual.allowedMimeTypes) !== sorted(allowedMimeTypes)) {
        issues.push({
          field: "allowedMimeTypes",
          expected: allowedMimeTypes,
          actual: actual.allowedMimeTypes,
          message: `Bucket "${config.id}" allowed MIME types differ`,
        });
      }
      return issues;
    },
    connect: (client, options = {}) =>
      connectBucket(
        bucket,
        client,
        resolve,
        options,
        tenantGuard(
          bucket.id,
          tenantParam,
          tenantClaim,
          (path) => bucket.match(path),
          options,
        ),
      ),
  };
  return bucket;
}

function bodyInfo(
  body: UploadBody,
  contentType: string | undefined,
): { size?: number; type?: string } {
  const info: { size?: number; type?: string } = {};
  if (typeof Blob !== "undefined" && body instanceof Blob) {
    info.size = body.size;
    if (body.type) info.type = body.type;
  } else if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) {
    info.size = body.byteLength;
  }
  if (contentType) info.type = contentType;
  return info;
}

function ttlSeconds(ttl: number | TtlPreset | undefined): number {
  return typeof ttl === "number" ? ttl : TTL[ttl ?? "hour"];
}

function isErrorResult(value: unknown): value is { ok: false; error: DbError } {
  // SAFETY: value is a non-null object here, and each property read is type-checked.
  return (
    typeof value === "object" &&
    value !== null &&
    (value as { ok?: unknown }).ok === false &&
    "error" in value
  );
}

function connectBucket<P extends string, Id extends string>(
  bucket: Bucket<P, Id>,
  client: StorageClient,
  resolveTarget: (target: ObjectTarget<P, Id>) => StoragePath<Id>,
  connectOptions: BucketConnectOptions,
  guard: TenantGuard | undefined,
): BucketClient<P, Id> {
  const resolve = (target: ObjectTarget<P, Id>): StoragePath<Id> => {
    const path = resolveTarget(target);
    return guard ? guard.path(path) : path;
  };
  const scopedWithin = (
    within: Partial<TemplateValues<P>> | undefined,
  ): Partial<TemplateValues<P>> =>
    guard ? { ...within, [guard.param]: guard.within(within) } : (within ?? {});
  const api = () => client.storage.from(bucket.id);
  const signed = connectOptions.cacheSignedUrls
    ? new Map<string, { readonly url: string; readonly until: number }>()
    : undefined;
  const run = <T>(
    fn: () => PromiseLike<{ data: T; error: unknown }>,
  ): AsyncResult<NonNullable<T>> =>
    AsyncResult.from(async () => {
      try {
        const { data, error } = await fn();
        // SAFETY: the null check above excludes null data.
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

  const upload: BucketClient<P, Id>["upload"] = (target, body, options) =>
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

  const remove: BucketClient<P, Id>["remove"] = (targets) =>
    AsyncResult.from(async () => {
      const paths = targets.map(resolve);
      if (paths.length === 0) return ok([]);
      return run(() => api().remove(paths)).map(() => paths);
    });

  const transfer =
    (method: "copy" | "move"): BucketClient<P, Id>["copy"] =>
    (from, to) =>
      AsyncResult.from(async () => {
        const [source, path] = [resolve(from), resolve(to)];
        const result = run<unknown>(() => api()[method](source, path));
        return result.map(() => ({ path }));
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
        { limit, offset, sortBy: { column: "name", order: "asc" } },
        signal ? { signal } : {},
      );
      if (error) throw new DbException(fromStorageError(error, bucket.id));
      for (const item of data) {
        const path = folder ? `${folder}/${item.name}` : item.name;
        if (item.id === null) await walk(path, signal, out);
        else {
          // SAFETY: Storage returns object metadata as JSON with optional size
          // and type fields.
          const metadata = (item.metadata ?? {}) as {
            size?: number;
            mimetype?: string;
          };
          out.push({
            path,
            ...(typeof metadata.size === "number"
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

  const list: BucketClient<P, Id>["list"] = (within, options) =>
    AsyncResult.from(async () => {
      const out: StoredObject[] = [];
      await walk(bucket.prefix(scopedWithin(within)), options?.signal, out);
      return ok(out);
    }).mapError((error) => ({ ...error, table: bucket.id }));

  const signedUrl: BucketClient<P, Id>["signedUrl"] = (target, options) =>
    AsyncResult.from(async () => {
      const path = resolve(target);
      const ttl = ttlSeconds(options?.ttl);
      const key = signed
        ? JSON.stringify([path, ttl, options?.transform, options?.download])
        : "";
      const cached = signed?.get(key);
      if (cached && cached.until > Date.now()) return ok(cached.url);
      const result = await run(() =>
        api().createSignedUrl(path, ttl, {
          ...download(options?.download),
          ...(options?.transform
            ? { transform: { ...options.transform } }
            : {}),
        }),
      ).map((data) => data.signedUrl);
      if (signed && result.ok) {
        const margin = Math.min(60, ttl / 10);
        signed.set(key, {
          url: result.data,
          until: Date.now() + (ttl - margin) * 1000,
        });
      }
      return result;
    });

  return {
    bucket,
    path: (target) => {
      try {
        return ok(resolve(target));
      } catch (cause) {
        return err(toDbError(cause));
      }
    },
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
    copy: transfer("copy"),
    move: transfer("move"),
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
        ).andThen((data) => {
          const failed = data.find(
            (entry) => entry.error != null || !entry.signedUrl,
          );
          if (failed)
            return Promise.resolve(
              err(
                dbError(
                  "not_found",
                  failed.error ?? `No URL for ${String(failed.path)}`,
                  { table: bucket.id },
                ),
              ),
            );
          // SAFETY: the failure check above returned early, so every entry has
          // a signed URL.
          return Promise.resolve(ok(data.map((entry) => entry.signedUrl!)));
        });
      }),
    publicUrl(target, options) {
      try {
        return ok(
          api().getPublicUrl(resolve(target), {
            ...download(options?.download),
            ...(options?.transform
              ? { transform: { ...options.transform } }
              : {}),
          }).data.publicUrl,
        );
      } catch (cause) {
        return err(toDbError(cause));
      }
    },
    renderUrl(target, transform, options) {
      if (!bucket.public) return signedUrl(target, { ...options, transform });
      return AsyncResult.from(() =>
        Promise.resolve(
          ok(
            api().getPublicUrl(resolve(target), {
              ...download(options?.download),
              transform: { ...transform },
            }).data.publicUrl,
          ),
        ),
      );
    },
    replace: (target, body, options = {}) =>
      AsyncResult.from<ReplaceResult<Id>>(async () => {
        const path = resolve(target);
        const previous =
          options.previous == null ? null : resolve(options.previous);
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
        const namespace = optionalTemporal();
        if (namespace === undefined) return err(temporalMissing());
        const now = options.now?.() ?? namespace.Now.instant();
        const cutoff =
          options.olderThan instanceof namespace.Instant
            ? options.olderThan.epochMilliseconds
            : now.epochMilliseconds - options.olderThan.total("milliseconds");
        const found = await list(
          options.within,
          options.signal ? { signal: options.signal } : undefined,
        );
        if (!found.ok) return found;
        const scope = scopedWithin(options.within);
        const candidates = found.data
          .filter((object) => inScope(bucket.match(object.path), scope))
          .filter((object) => {
            // Storage sends ISO text; epoch milliseconds compare directly.
            const created = Date.parse(
              object.createdAt ?? object.updatedAt ?? "",
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
