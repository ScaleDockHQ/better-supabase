import type { AccessBucketPolicy, BucketPolicyName } from "../schema/types.ts";

import { accessCheck } from "../core/access-sql.ts";

/** The SQL conditions of a permission-based bucket policy. */
export interface PolicyChecks {
  readonly read: string;
  readonly list?: string;
  readonly write: string;
  readonly delete: string;
}

/**
 * The checks of an access policy, or `undefined` for a named policy.
 * `segmentOf` returns the tenant segment, or throws when the path has none.
 */
export function policyChecks(
  config: { readonly id: string },
  policy: BucketPolicyName | AccessBucketPolicy,
  segmentOf: (kind: string) => number,
): PolicyChecks | undefined {
  if (typeof policy === "string") return undefined;
  const where = `defineBucket(${config.id})`;
  const segment =
    policy.segment ??
    (policy.scope === "platform" ? undefined : segmentOf("permission"));
  const id =
    segment === undefined || policy.scope === "platform"
      ? undefined
      : `split_part(name, '/', ${String(segment)})`;
  const check = (key: string): string => accessCheck(where, policy, key, id);
  const keys = policy.access;
  return {
    read: check(keys.read),
    ...(keys.list === undefined ? {} : { list: check(keys.list) }),
    write: check(keys.write),
    delete: check(keys.delete ?? keys.write),
  };
}
