import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { SqlClient } from "../../postgres/executor.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { blockCall, run } from "../shared.ts";

/** The Stripe event sent when a customer's active entitlements change. */
export const ENTITLEMENTS_UPDATED =
  "entitlements.active_entitlement_summary.updated";

function stripeCustomerOf(payload: unknown): string | undefined {
  if (typeof payload !== "object" || payload === null) {
    return undefined;
  }

  // SAFETY: payload is a non-null object, and every nested field is optional and checked.
  const object = (payload as { data?: { object?: { customer?: unknown } } })
    .data?.object;

  const customer = object?.customer;

  if (typeof customer === "string") {
    return customer;
  }

  // SAFETY: a Stripe customer is an id string or an object with an id; the
  // string case returned above.
  const id = (customer as { id?: unknown } | undefined)?.id;

  return typeof id === "string" ? id : undefined;
}

/**
 * Users whose `memberships` claim carries the entitlements of the Stripe
 * customer in an `entitlements.active_entitlement_summary.updated` event, so a
 * job can invalidate their sessions. Empty for other payloads.
 */
export function entitlementMembers(
  sql: SqlClient,
  payload: unknown,
): AsyncResult<readonly string[]> {
  const customer = stripeCustomerOf(payload);

  if (customer === undefined) {
    return AsyncResult.ok([]);
  }

  return run(() =>
    sql.queryRaw<{ user_id: string }>(
      "select user_id from better_supabase.entitlement_members($1) as user_id",
      [customer],
    ),
  ).map((rows) => rows.map((row) => row.user_id));
}

export interface EntitlementsOptions {
  /**
   * The member's transport: `sqlTransport(postgres.asUser(claims))` or
   * `rpcTransport(supabase)`.
   */
  readonly transport: BlockTransport;
  /** The module's schema, or its API schema. Default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** `withBlockHooks` hooks around `has` and `value`. */
  readonly hooks?: BlockHooks<Entitlements>;
  /** Receives the errors `after` hooks throw. */
  readonly logger?: Logger;
}

/**
 * A member's reads of the tenant's entitlements, as `has_entitlement` and
 * `entitlement_value` check them.
 */
export interface Entitlements {
  /** Whether the tenant has `key`; `false` when the caller is not a member. */
  has(input: { organizationId: string; key: string }): AsyncResult<boolean>;
  /**
   * The feature's value: a number or text from the plan catalog's value column,
   * `true` for a feature without one, and `undefined` when the tenant lacks it
   * or the caller is not a member.
   */
  value(input: { organizationId: string; key: string }): AsyncResult<unknown>;
  /**
   * Succeeds when the tenant has `key`, and otherwise fails with a `forbidden`
   * error whose `permission` is `entitlement:<key>`, so a route or action can
   * answer "upgrade your plan" with `.orThrow()` or a plain return.
   */
  // A property, not a method signature: the WinterTC check flags `require(` as a CommonJS call.
  require: (input: {
    organizationId: string;
    key: string;
  }) => AsyncResult<true>;
  /**
   * The seats the tenant's plan leaves: its numeric `key` entitlement (default
   * `seats`) minus `used`, never below 0. `undefined` when the plan sets no
   * number, which means no limit. Pass the member count as `used`; it is
   * `organizations.members(...)` length, or a billing seat count.
   */
  seatsLeft(input: {
    organizationId: string;
    used: number;
    key?: string | undefined;
  }): AsyncResult<number | undefined>;
  /** `has` for each key, in one result keyed by feature. */
  all(input: {
    organizationId: string;
    keys: readonly string[];
  }): AsyncResult<Readonly<Record<string, boolean>>>;
}

/**
 * Reads the caller's entitlements through the `entitlements` module's
 * `has_entitlement` and `entitlement_value`, which check membership.
 */
export function createEntitlements(options: EntitlementsOptions): Entitlements {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: Entitlements = {
    has: ({ organizationId, key }) =>
      call(
        "has_entitlement",
        { tenant: organizationId, key },
        (value) => value === true,
      ),
    value: ({ organizationId, key }) =>
      call("entitlement_value", { tenant: organizationId, key }, (value) =>
        value === null ? undefined : value,
      ),
    require: ({ organizationId, key }) =>
      hooked
        .has({ organizationId, key })
        .andThen((has) =>
          Promise.resolve(
            has
              ? ok(true as const)
              : err(
                  dbError("forbidden", `The plan does not include ${key}`, {
                    permission: `entitlement:${key}`,
                  }),
                ),
          ),
        ),
    seatsLeft: ({ organizationId, used, key = "seats" }) =>
      hooked.value({ organizationId, key }).map((limit) => {
        const total = typeof limit === "number" ? limit : Number(limit);

        return limit === undefined || !Number.isFinite(total)
          ? undefined
          : Math.max(0, total - used);
      }),
    all: ({ organizationId, keys }) =>
      AsyncResult.from(async () => {
        const entries: [string, boolean][] = [];

        for (const key of keys) {
          const has = await hooked.has({ organizationId, key });

          if (!has.ok) {
            return has;
          }

          entries.push([key, has.data]);
        }

        return ok(Object.fromEntries(entries));
      }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Entitlements = withBlockHooks(client, options.hooks, {
    block: "entitlements",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
