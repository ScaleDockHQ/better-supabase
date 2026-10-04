import type { PermdockCatalog } from "../core/permdock-sql.ts";
import type {
  AccessBucketPolicy,
  BucketPolicyName,
  PermdockBucketPolicy,
} from "../schema/types.ts";

import { permdockCheck } from "../core/permdock-sql.ts";
import { sqlString } from "../core/template.ts";

/** The SQL conditions of a permission-based bucket policy. */
export interface PolicyChecks {
  readonly read: string;
  readonly list?: string;
  readonly write: string;
  readonly delete: string;
}

/**
 * The checks of a PermDock or access contract policy, or `undefined` for a
 * named policy. `segmentOf` returns the tenant segment, or throws when the
 * path has none.
 */
export function policyChecks(
  config: { readonly id: string; readonly catalog?: PermdockCatalog },
  policy: BucketPolicyName | PermdockBucketPolicy | AccessBucketPolicy,
  segmentOf: (kind: string) => number,
): PolicyChecks | undefined {
  if (typeof policy === "string") return undefined;
  let check: (key: string) => string;
  let keys: PermdockBucketPolicy["permdock"];
  if ("permdock" in policy) {
    const where = `defineBucket(${config.id})`;
    const id =
      policy.scope === "global"
        ? undefined
        : `split_part(name, '/', ${String(policy.segment ?? segmentOf("PermDock"))})`;
    check = (key) => permdockCheck(where, policy, key, id, config.catalog);
    keys = policy.permdock;
  } else {
    const segment =
      policy.segment ??
      (policy.scope === "platform" ? undefined : segmentOf("permission"));
    check = (key) =>
      segment === undefined
        ? `(select better_supabase.is_platform(${sqlString(key)}))`
        : `split_part(name, '/', ${String(segment)}) in (select t::text from better_supabase.tenant_ids_with(${sqlString(key)}) t)`;
    keys = policy.access;
  }
  return {
    read: check(keys.read),
    ...(keys.list === undefined ? {} : { list: check(keys.list) }),
    write: check(keys.write),
    delete: check(keys.delete ?? keys.write),
  };
}
