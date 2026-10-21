export interface EntitlementsConfig {
  /**
   * `table.column` (or `schema.table.column`) holding each tenant's Stripe
   * customer id, read by the `entitlements` SQL module. Required without the
   * `organizations` module; with it, defaults to the `stripe_customer_id`
   * column that module adds.
   */
  readonly customer?: string;
  /** The tenant id column of that table. Defaults to `id`. */
  readonly key?: string;
  /**
   * Where `has_entitlement` and `feature_claims` read memberships from.
   * `"provider"` calls the authorization provider's `memberIds` and
   * `memberIdsFor` functions; `"tenant"` reads `better_supabase.memberships`.
   * Defaults to `"provider"` when `authorization` is set, else `"tenant"`.
   */
  readonly memberships?: "tenant" | "provider";
  /**
   * Where each tenant's entitlements come from. `"stripe-sync"` (the default)
   * reads the Stripe Sync Engine's `stripe.active_entitlements` through
   * `customer`. `{ plans }` reads a plan catalog: the tenant's active
   * subscription and the features its plan includes. `"custom"` leaves
   * `better_supabase.tenant_entitlements(tenant)` to you; the module writes the
   * checks and the claim over it.
   */
  readonly source?: "stripe-sync" | "custom" | EntitlementPlansSource;
  /**
   * The shape of the features claim `feature_claims` writes, which every token
   * carries. `false` writes `{}` (check entitlements in SQL with
   * `has_entitlement` only); `maxTenants` keeps at most that many tenants;
   * `keys` writes short codes instead of the feature keys. Pass the same `keys`
   * to `hasEntitlement`.
   */
  readonly claim?:
    | false
    | {
        readonly maxTenants?: number;
        readonly keys?: Readonly<Record<string, string>>;
      };
}

/** `entitlements.source.plans`: a plan catalog in your own tables. */
export interface EntitlementPlansSource {
  readonly plans: {
    readonly subscriptions: {
      /** `table` or `schema.table`. */
      readonly table: string;
      /** The tenant id column. */
      readonly tenant: string;
      /** The plan key column. */
      readonly plan: string;
      /** A status column; with it, only rows in `activeStatuses` count. */
      readonly status?: string;
      /** Defaults to `["active", "trialing"]`. */
      readonly activeStatuses?: readonly string[];
    };
    readonly features: {
      /** `table` or `schema.table`. */
      readonly table: string;
      /** The plan key column. */
      readonly plan: string;
      /** The feature key column: what `has_entitlement` and the claim name. */
      readonly feature: string;
      /** A boolean column; with it, only included features count. */
      readonly included?: string;
      /**
       * A column with the feature's value (a number, text or jsonb), such as a
       * limit, that `tenant_entitlement_value` returns.
       */
      readonly value?: string;
    };
  };
}
