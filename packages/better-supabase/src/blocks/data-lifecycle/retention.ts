import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RETENTION_KINDS } from "../../sql/modules/data-lifecycle-retention.ts";

import {
  applyTemporal,
  blockCall,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
  type BlockTemporalOptions,
} from "../shared.ts";

/** A kind the modules' purges look up; an app's own purges may use any other. */
export type RetentionKind = (typeof RETENTION_KINDS)[number] | (string & {});

export interface RetentionPolicy {
  readonly id: string;
  readonly kind: RetentionKind;
  /** Postgres interval text, such as `7 years`. */
  readonly keep: string;
  /** Set for one tenant's policy. */
  readonly organizationId: string | undefined;
  /** Set for the policy of a plan's tenants. */
  readonly plan: string | undefined;
  readonly updatedAt: Temporal.Instant;
}

export interface LegalHold {
  readonly id: string;
  /** Absent for a hold on every tenant. */
  readonly organizationId: string | undefined;
  /** Absent for a hold on every kind. */
  readonly kind: RetentionKind | undefined;
  readonly reason: string;
  readonly placedBy: string | undefined;
  readonly placedAt: Temporal.Instant;
  readonly releasedBy: string | undefined;
  readonly releasedAt: Temporal.Instant | undefined;
}

/**
 * Who a policy applies to: one tenant, a plan's tenants, or every tenant
 * (neither).
 */
export type RetentionScope =
  | { readonly organizationId: string; readonly plan?: never }
  | { readonly plan: string; readonly organizationId?: never }
  | { readonly organizationId?: never; readonly plan?: never };

export interface RetentionOptions extends BlockTemporalOptions {
  /** A service-role transport: the functions are granted to `service_role` only. */
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Retention {
  /**
   * Keeps `kind` for `keep` (an interval such as `7 years` or a
   * `Temporal.Duration`), replacing the scope's earlier policy. A purge keeps
   * rows for the policy whatever its own `older_than`.
   */
  setPolicy(
    kind: RetentionKind,
    keep: Temporal.Duration | string,
    scope?: RetentionScope,
  ): AsyncResult<RetentionPolicy>;
  /** `false` when the scope had no policy for `kind`. */
  removePolicy(
    kind: RetentionKind,
    scope?: RetentionScope,
  ): AsyncResult<boolean>;
  policies(kind?: RetentionKind): AsyncResult<readonly RetentionPolicy[]>;
  /**
   * Stops every purge (and the organization purge) from deleting what the hold
   * covers: one tenant or all, one kind or all.
   */
  placeHold(hold: {
    readonly reason: string;
    readonly organizationId?: string;
    readonly kind?: RetentionKind;
  }): AsyncResult<LegalHold>;
  /** `undefined` when no active hold has this id. */
  releaseHold(id: string): AsyncResult<LegalHold | undefined>;
  holds(options?: {
    readonly includeReleased?: boolean;
  }): AsyncResult<readonly LegalHold[]>;
}

function policyOf(value: unknown): RetentionPolicy {
  const row = recordOf(value, "retention_policies");

  return {
    id: textOf(row["id"]),
    kind: textOf(row["kind"]),
    keep: textOf(row["keep"]),
    organizationId: optionalText(row["organization_id"]),
    plan: optionalText(row["plan"]),
    updatedAt: toInstant(textOf(row["updated_at"])),
  };
}

function holdOf(value: unknown): LegalHold {
  const row = recordOf(value, "legal_holds");

  return {
    id: textOf(row["id"]),
    organizationId: optionalText(row["organization_id"]),
    kind: optionalText(row["kind"]),
    reason: textOf(row["reason"]),
    placedBy: optionalText(row["placed_by"]),
    placedAt: toInstant(textOf(row["placed_at"])),
    releasedBy: optionalText(row["released_by"]),
    releasedAt: optionalInstant(row["released_at"]),
  };
}

/** Retention policies and legal holds, as the service role. */
export function createRetention(options: RetentionOptions): Retention {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const scoped = (scope: RetentionScope = {}) => ({
    tenant: scope.organizationId,
    plan: scope.plan,
  });

  return {
    setPolicy: (kind, keep, scope) =>
      call(
        "set_retention_policy",
        { kind, keep: String(keep), ...scoped(scope) },
        policyOf,
      ),
    removePolicy: (kind, scope) =>
      call(
        "remove_retention_policy",
        { kind, ...scoped(scope) },
        (value) => value === true,
      ),
    policies: (kind) =>
      call("list_retention_policies", { kind }, (value) =>
        recordsOf(value, "list_retention_policies").map(policyOf),
      ),
    placeHold: (hold) =>
      call(
        "place_legal_hold",
        { reason: hold.reason, tenant: hold.organizationId, kind: hold.kind },
        holdOf,
      ),
    releaseHold: (id) =>
      call("release_legal_hold", { id }, (value) =>
        isRecord(value) ? holdOf(value) : undefined,
      ),
    holds: (request = {}) =>
      call(
        "list_legal_holds",
        { include_released: request.includeReleased ?? false },
        (value) => recordsOf(value, "list_legal_holds").map(holdOf),
      ),
  };
}
