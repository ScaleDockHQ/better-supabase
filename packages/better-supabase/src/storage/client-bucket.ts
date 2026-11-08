import type { DbError } from "../core/errors.ts";
import type { TemplateParams } from "../core/template.ts";
import type {
  BucketConfig,
  ClientBucket,
  ObjectTarget,
  PathValues,
  TransformOptions,
} from "./bucket.ts";
import type { Layouts } from "./layouts.ts";
import type { StoragePath } from "./path.ts";

import { DbException, dbError } from "../core/errors.ts";
import { err, ok, toDbError } from "../core/result.ts";
import { connectBucket } from "./connect.ts";
import { pathLayouts } from "./layouts.ts";
import { tenantGuard } from "./tenant-scope.ts";
import { checkVariants } from "./variants.ts";

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
  if (typeof value === "number") {
    return value;
  }

  const match = /^\s*(\d+(?:\.\d+)?)\s*([a-z]*)\s*$/i.exec(value);
  // oxlint-disable-next-line typescript/prefer-nullish-coalescing -- an empty unit means bytes.
  const unit = SIZE_UNITS[(match?.[2] || "b").toLowerCase()];

  if (!match || unit === undefined) {
    throw new TypeError(`Invalid size "${value}"`);
  }

  return Math.round(Number(match[1]) * unit);
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

export function sizeLabel(bytes: number): string {
  for (const [unit, size] of [
    ["GiB", 1024 ** 3],
    ["MiB", 1024 ** 2],
    ["KiB", 1024],
  ] as const) {
    if (bytes >= size && bytes % size === 0) {
      return `${String(bytes / size)}${unit}`;
    }
  }

  return `${String(bytes)}B`;
}

export interface BucketBase<
  P extends string,
  Id extends string,
  V extends string,
> {
  readonly bucket: ClientBucket<P, Id, V>;
  readonly layouts: Layouts;
}

/**
 * Everything a bucket does without SQL, `config.toml`, drift checks or the
 * admin API: paths, limits, variants and `connect`. `defineBucket` from
 * `better-supabase/storage` adds the server methods on top.
 */
export function createBucketBase<
  const P extends string,
  const Id extends string,
  const V extends string,
>(
  config: BucketConfig<P, Id, V>,
  sqlString: (value: string) => string,
): BucketBase<P, Id, V> {
  const layouts = pathLayouts(config.id, config.path, sqlString);
  const policy = config.policy ?? "none";

  // SAFETY: without config.variants the bucket has no variant names.
  const variants = Object.freeze({ ...config.variants }) as Readonly<
    Record<V, TransformOptions>
  >;

  checkVariants(config.id, variants);

  const fileSizeLimit =
    config.fileSizeLimit === undefined
      ? undefined
      : parseSize(config.fileSizeLimit);

  const allowedMimeTypes = config.allowedMimeTypes;
  const versioning = config.versioning ?? false;

  const tenantParam = config.tenant
    ? (config.tenant.param ?? "organizationId")
    : undefined;

  if (tenantParam !== undefined) {
    layouts.requireParam(tenantParam, "tenant.param");
  }

  const tenantClaim = config.tenant?.claim;

  const resolve = (target: ObjectTarget<P, Id>): StoragePath<Id> => {
    if (typeof target !== "string") {
      // SAFETY: a template builds the path from typed values, so it matches
      // the bucket's paths.
      return layouts.build(target) as StoragePath<Id>;
    }

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
  const bucket: ClientBucket<P, Id, V> = {
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
    versioning,
    lifecycle: config.lifecycle,
    variants,
    path: (values) => {
      try {
        // SAFETY: the template builds the path from typed values.
        return ok(layouts.build(values) as StoragePath<Id>);
      } catch (cause) {
        return err(toDbError(cause));
      }
    },
    // SAFETY: match returns the parameters of P.
    match: (path) => layouts.match(path) as PathValues<P> | null,
    prefix: (values = {}) => layouts.prefix(values),
    check,
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

  return { bucket, layouts };
}
