import type { BlockTransport } from "../../core/block-transport.ts";

import {
  DEFAULT_BLOCK_SCHEMA,
  errorText,
  isRecord,
  optionalText,
  recordsOf,
  stringsOf,
  textOf,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";

export type FlagType = "boolean" | "string" | "number" | "object";

export type FlagValue =
  | boolean
  | string
  | number
  | null
  | FlagValue[]
  | { [key: string]: FlagValue };

/** A targeting rule: every list that is set must contain the caller's value. */
export interface FlagRule {
  readonly variant: string;
  readonly tenants?: readonly string[];
  readonly users?: readonly string[];
  /** Entitlement lookup keys; one match is enough. */
  readonly plans?: readonly string[];
  readonly roles?: readonly string[];
}

export interface FlagOverride {
  readonly organizationId: string | undefined;
  readonly userId: string | undefined;
  readonly variant: string;
}

/** A row of the `flags` table with its overrides (`flag_definitions()`). */
export interface FlagDefinition {
  readonly key: string;
  readonly type: FlagType;
  readonly variants: Readonly<Record<string, FlagValue>>;
  readonly defaultVariant: string;
  readonly enabled: boolean;
  readonly rules: readonly FlagRule[];
  /** 0 to 100, in steps of 0.01. */
  readonly rolloutPercentage: number;
  readonly rolloutVariant: string | undefined;
  readonly overrides: readonly FlagOverride[];
}

/**
 * The OpenFeature evaluation context the provider reads. `targetingKey` is
 * the user id; without one, the rollout buckets by `tenant`.
 */
export interface FlagContext {
  readonly targetingKey?: string;
  readonly tenant?: string;
  readonly plans?: readonly string[];
  readonly role?: string;
  /** Every role the caller holds in the tenant; a `roles` rule matches any of them. */
  readonly roles?: readonly string[];
  readonly [attribute: string]: unknown;
}

/**
 * What `flagContext()` returns; an OpenFeature `EvaluationContext`. It is a
 * type alias because an interface has no implicit index signature.
 */
export type RequestFlagContext = {
  targetingKey?: string;
  tenant?: string;
  plans?: string[];
  role?: string;
  roles?: string[];
};

export type FlagReason =
  | "DISABLED"
  | "TARGETING_MATCH"
  | "SPLIT"
  | "DEFAULT"
  | "ERROR";

export type FlagErrorCode =
  | "FLAG_NOT_FOUND"
  | "TYPE_MISMATCH"
  | "PROVIDER_NOT_READY"
  | "GENERAL";

/**
 * The shape of an OpenFeature `ResolutionDetails`. `Code` is the type of
 * `errorCode`: OpenFeature's `ErrorCode` when `errorCodes: ErrorCode` is
 * passed to the provider, the matching string literals otherwise.
 */
export interface FlagResolution<T, Code extends string = FlagErrorCode> {
  readonly value: T;
  readonly variant?: string;
  readonly reason: FlagReason;
  readonly errorCode?: Code;
  readonly errorMessage?: string;
}

/** The shape of an OpenFeature `EvaluationDetails`. */
export interface FlagDetails<
  T,
  Code extends string = FlagErrorCode,
> extends FlagResolution<T, Code> {
  readonly flagKey: string;
  readonly flagMetadata: Readonly<Record<string, string | number | boolean>>;
}

const BUCKETS = 10_000;

/**
 * The rollout bucket of `target` for `flag`, 0 to 9999: the first 32 bits
 * of SHA-256(`flag.target`) modulo 10000. `better_supabase.flag_bucket()`
 * computes the same number, so SQL and TypeScript agree on who is in.
 */
export async function flagBucket(
  flag: string,
  target: string,
): Promise<number> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${flag}.${target}`),
  );
  return new DataView(digest).getUint32(0) % BUCKETS;
}

const contains = (
  list: readonly string[] | undefined,
  value: string | undefined,
): boolean =>
  list === undefined || (value !== undefined && list.includes(value));

const anyIn = (
  list: readonly string[] | undefined,
  values: readonly string[],
): boolean =>
  list === undefined || values.some((value) => list.includes(value));

function ruleMatches(rule: FlagRule, context: FlagContext): boolean {
  return (
    contains(rule.tenants, context.tenant) &&
    contains(rule.users, context.targetingKey) &&
    anyIn(rule.roles, [
      ...(context.role === undefined ? [] : [context.role]),
      ...(context.roles ?? []),
    ]) &&
    (rule.plans === undefined ||
      rule.plans.some((plan) => context.plans?.includes(plan) === true))
  );
}

async function chooseVariant(
  flag: FlagDefinition,
  context: FlagContext,
): Promise<{ variant: string; reason: FlagReason }> {
  if (!flag.enabled)
    return { variant: flag.defaultVariant, reason: "DISABLED" };
  const override =
    flag.overrides.find(
      (entry) =>
        entry.userId !== undefined && entry.userId === context.targetingKey,
    ) ??
    flag.overrides.find(
      (entry) =>
        entry.organizationId !== undefined &&
        entry.organizationId === context.tenant,
    );
  let chosen = override?.variant;
  let reason: FlagReason = chosen === undefined ? "DEFAULT" : "TARGETING_MATCH";
  if (chosen === undefined) {
    const rule = flag.rules.find((entry) => ruleMatches(entry, context));
    if (rule) {
      chosen = rule.variant;
      reason = "TARGETING_MATCH";
    }
  }
  const target = context.targetingKey ?? context.tenant;
  if (
    chosen === undefined &&
    flag.rolloutVariant !== undefined &&
    target !== undefined &&
    (await flagBucket(flag.key, target)) < flag.rolloutPercentage * 100
  ) {
    chosen = flag.rolloutVariant;
    reason = "SPLIT";
  }
  if (chosen === undefined || !Object.hasOwn(flag.variants, chosen)) {
    return { variant: flag.defaultVariant, reason: "DEFAULT" };
  }
  return { variant: chosen, reason };
}

/** The result of `evaluateFlag()`, which never fails. */
export interface FlagEvaluation {
  readonly value: FlagValue;
  readonly variant: string;
  readonly reason: FlagReason;
}

/** Evaluates one flag as `better_supabase.flag_evaluation()` does. */
export async function evaluateFlag(
  flag: FlagDefinition,
  context: FlagContext = {},
): Promise<FlagEvaluation> {
  const { variant, reason } = await chooseVariant(flag, context);
  return { value: flag.variants[variant] ?? null, variant, reason };
}

const FLAG_TYPES: ReadonlySet<string> = new Set([
  "boolean",
  "string",
  "number",
  "object",
]);

const flagTypeOf = (value: unknown): FlagType => {
  const text = textOf(value);
  // SAFETY: checked against the types the flags table's check allows.
  return FLAG_TYPES.has(text) ? (text as FlagType) : "boolean";
};

function ruleOf(value: unknown): FlagRule | undefined {
  if (!isRecord(value) || typeof value["variant"] !== "string")
    return undefined;
  const list = (key: string): readonly string[] | undefined =>
    Array.isArray(value[key]) ? stringsOf(value[key]) : undefined;
  const tenants = list("tenants");
  const users = list("users");
  const plans = list("plans");
  const roles = list("roles");
  return {
    variant: value["variant"],
    ...(tenants && { tenants }),
    ...(users && { users }),
    ...(plans && { plans }),
    ...(roles && { roles }),
  };
}

/** Parses the rows of `flag_definitions()`. */
export function flagDefinitionsOf(value: unknown): readonly FlagDefinition[] {
  return recordsOf(value, "flag_definitions").map((row) => ({
    key: textOf(row["key"]),
    type: flagTypeOf(row["type"]),
    // SAFETY: a jsonb object column; its values are JSON.
    variants: (isRecord(row["variants"]) ? row["variants"] : {}) as Record<
      string,
      FlagValue
    >,
    defaultVariant: optionalText(row["default_variant"]) ?? "",
    enabled: row["enabled"] !== false,
    rules: (Array.isArray(row["rules"]) ? row["rules"] : []).flatMap((rule) => {
      const parsed = ruleOf(rule);
      return parsed ? [parsed] : [];
    }),
    rolloutPercentage: Number(row["rollout_percentage"] ?? 0),
    rolloutVariant: optionalText(row["rollout_variant"]),
    overrides: recordsOf(row["overrides"] ?? [], "flag_definitions").map(
      (entry) => ({
        organizationId: optionalText(entry["organization_id"]),
        userId: optionalText(entry["user_id"]),
        variant: textOf(entry["variant"]),
      }),
    ),
  }));
}

export interface FlagsProviderOptions<
  Code extends string = FlagErrorCode,
> extends BlockTemporalOptions {
  /**
   * A service-role transport: `flag_definitions()` is granted to
   * `service_role` only, as it lists every override.
   */
  readonly transport?: BlockTransport;
  /** The module schema (`sql.modules.flags.schema`), default `better_supabase`. */
  readonly schema?: string;
  /** How long the definitions are cached, in milliseconds. Default 30000. */
  readonly ttl?: number;
  /** Fixed definitions instead of a transport, for tests and static flags. */
  readonly definitions?: readonly FlagDefinition[];
  /**
   * OpenFeature's `ErrorCode` enum (from `@openfeature/core` or
   * `@openfeature/server-sdk`), so the provider's types match `Provider`.
   */
  readonly errorCodes?: Readonly<Record<FlagErrorCode, Code>>;
  readonly now?: () => number;
}

/**
 * The shape of an OpenFeature server `Provider`. Pass it to
 * `OpenFeature.setProviderAndWait()`; this package never imports OpenFeature.
 */
export interface FlagsProvider<Code extends string = FlagErrorCode> {
  readonly metadata: { readonly name: string };
  readonly runsOn: "server";
  initialize(context?: FlagContext): Promise<void>;
  resolveBooleanEvaluation(
    flagKey: string,
    defaultValue: boolean,
    context: FlagContext,
  ): Promise<FlagResolution<boolean, Code>>;
  resolveStringEvaluation(
    flagKey: string,
    defaultValue: string,
    context: FlagContext,
  ): Promise<FlagResolution<string, Code>>;
  resolveNumberEvaluation(
    flagKey: string,
    defaultValue: number,
    context: FlagContext,
  ): Promise<FlagResolution<number, Code>>;
  resolveObjectEvaluation<T extends FlagValue>(
    flagKey: string,
    defaultValue: T,
    context: FlagContext,
  ): Promise<FlagResolution<T, Code>>;
  /** Drops the cache, so the next evaluation reloads the definitions. */
  refresh(): void;
}

const DEFAULT_CODES: Readonly<Record<FlagErrorCode, FlagErrorCode>> = {
  FLAG_NOT_FOUND: "FLAG_NOT_FOUND",
  TYPE_MISMATCH: "TYPE_MISMATCH",
  PROVIDER_NOT_READY: "PROVIDER_NOT_READY",
  GENERAL: "GENERAL",
};

type Check<T> = (value: FlagValue) => value is FlagValue & T;

const isBoolean: Check<boolean> = (value) => typeof value === "boolean";
const isString: Check<string> = (value) => typeof value === "string";
const isNumber: Check<number> = (value) => typeof value === "number";

/** Feature flags from the `flags` module, as an OpenFeature provider. */
export function createFlagsProvider<Code extends string = FlagErrorCode>(
  options: FlagsProviderOptions<Code>,
): FlagsProvider<Code> {
  applyTemporal(options);
  const { transport, definitions } = options;
  const schema = options.schema ?? DEFAULT_BLOCK_SCHEMA;
  const fetchFlags = definitions
    ? () => Promise.resolve(definitions)
    : transport
      ? async () =>
          flagDefinitionsOf(
            await transport.call(schema, "flag_definitions", {}),
          )
      : undefined;
  if (!fetchFlags) {
    throw new TypeError("createFlagsProvider needs a transport or definitions");
  }
  const ttl = options.ttl ?? 30_000;
  const now = options.now ?? Date.now;
  // SAFETY: without errorCodes, Code is its default, FlagErrorCode.
  const codes =
    options.errorCodes ?? (DEFAULT_CODES as Record<FlagErrorCode, Code>);
  let cache:
    | {
        readonly at: number;
        readonly flags: Promise<ReadonlyMap<string, FlagDefinition>>;
      }
    | undefined;

  const load = (): Promise<ReadonlyMap<string, FlagDefinition>> => {
    if (cache && now() - cache.at < ttl) return cache.flags;
    const flags = fetchFlags().then(
      (list) => new Map(list.map((flag) => [flag.key, flag])),
    );
    const entry = { at: now(), flags };
    cache = entry;
    flags.catch(() => {
      if (cache === entry) cache = undefined;
    });
    return flags;
  };

  async function resolve<T extends FlagValue>(
    flagKey: string,
    defaultValue: T,
    context: FlagContext,
    check: (value: FlagValue) => value is T,
  ): Promise<FlagResolution<T, Code>> {
    let flags: ReadonlyMap<string, FlagDefinition>;
    try {
      flags = await load();
    } catch (error) {
      return {
        value: defaultValue,
        reason: "ERROR",
        errorCode: codes.GENERAL,
        errorMessage: errorText(error),
      };
    }
    const flag = flags.get(flagKey);
    if (!flag) {
      return {
        value: defaultValue,
        reason: "ERROR",
        errorCode: codes.FLAG_NOT_FOUND,
        errorMessage: `Flag "${flagKey}" is not defined`,
      };
    }
    const result = await evaluateFlag(flag, context);
    if (!check(result.value)) {
      return {
        value: defaultValue,
        reason: "ERROR",
        errorCode: codes.TYPE_MISMATCH,
        errorMessage: `Flag "${flagKey}" is a ${flag.type} flag`,
      };
    }
    return {
      value: result.value,
      variant: result.variant,
      reason: result.reason,
    };
  }

  return {
    metadata: { name: "better-supabase" },
    runsOn: "server",
    async initialize() {
      await load();
    },
    resolveBooleanEvaluation: (flagKey, defaultValue, context) =>
      resolve(flagKey, defaultValue, context, isBoolean),
    resolveStringEvaluation: (flagKey, defaultValue, context) =>
      resolve(flagKey, defaultValue, context, isString),
    resolveNumberEvaluation: (flagKey, defaultValue, context) =>
      resolve(flagKey, defaultValue, context, isNumber),
    resolveObjectEvaluation: <T extends FlagValue>(
      flagKey: string,
      defaultValue: T,
      context: FlagContext,
    ) =>
      resolve(
        flagKey,
        defaultValue,
        context,
        (value): value is T => typeof value === "object" && value !== null,
      ),
    refresh() {
      cache = undefined;
    },
  };
}

/**
 * The four `get*Details` methods that the OpenFeature server `Client` and
 * the `FlagClient` of `@supabase-labs/middleware-openfeature` share.
 */
export interface FlagClient<Code extends string = FlagErrorCode> {
  getBooleanDetails(
    flagKey: string,
    defaultValue: boolean,
    context?: FlagContext,
  ): Promise<FlagDetails<boolean, Code>>;
  getStringDetails(
    flagKey: string,
    defaultValue: string,
    context?: FlagContext,
  ): Promise<FlagDetails<string, Code>>;
  getNumberDetails(
    flagKey: string,
    defaultValue: number,
    context?: FlagContext,
  ): Promise<FlagDetails<number, Code>>;
  getObjectDetails<T extends FlagValue>(
    flagKey: string,
    defaultValue: T,
    context?: FlagContext,
  ): Promise<FlagDetails<T, Code>>;
}

const details = async <T, Code extends string>(
  flagKey: string,
  resolution: Promise<FlagResolution<T, Code>>,
): Promise<FlagDetails<T, Code>> => ({
  flagKey,
  flagMetadata: {},
  ...(await resolution),
});

/**
 * A flag client without the OpenFeature SDK: `withOpenFeature({ client })`
 * from `@supabase-labs/middleware-openfeature` accepts it.
 */
export function createFlagClient<Code extends string = FlagErrorCode>(
  source: FlagsProvider<Code> | FlagsProviderOptions<Code>,
): FlagClient<Code> {
  const provider =
    "resolveBooleanEvaluation" in source ? source : createFlagsProvider(source);
  return {
    getBooleanDetails: (flagKey, defaultValue, context = {}) =>
      details(
        flagKey,
        provider.resolveBooleanEvaluation(flagKey, defaultValue, context),
      ),
    getStringDetails: (flagKey, defaultValue, context = {}) =>
      details(
        flagKey,
        provider.resolveStringEvaluation(flagKey, defaultValue, context),
      ),
    getNumberDetails: (flagKey, defaultValue, context = {}) =>
      details(
        flagKey,
        provider.resolveNumberEvaluation(flagKey, defaultValue, context),
      ),
    getObjectDetails: <T extends FlagValue>(
      flagKey: string,
      defaultValue: T,
      context: FlagContext = {},
    ) =>
      details(
        flagKey,
        provider.resolveObjectEvaluation(flagKey, defaultValue, context),
      ),
  };
}

export interface FlagContextSource {
  /** `ctx.jwtClaims` from `withBetterSupabase`, or verified claims. */
  readonly jwtClaims?: Readonly<Record<string, unknown>> | null | undefined;
  /** The active tenant; default the `tenant_id` claim. */
  readonly tenant?: string | null | undefined;
}

export interface FlagContextOptions {
  /** `config.claims.tenant`, default `tenant_id`. */
  readonly tenantClaim?: string;
  /** `config.claims.features`, default `features`. */
  readonly featuresClaim?: string;
  /** The claim the memberships hook writes, default `memberships`. */
  readonly membershipsClaim?: string;
  /**
   * The scope of tenant memberships when the claim is a list of entries, as
   * an authorization provider's hook may write it (`{ scope, id, roles }`). Without it, the entry
   * for the tenant id that has no `within` (a root scope) is read.
   */
  readonly membershipScope?: string;
  /** Reads the caller's roles in `tenant` from claims of another shape. */
  readonly roles?: (
    claims: Readonly<Record<string, unknown>>,
    tenant: string,
  ) => string | readonly string[] | undefined;
}

/**
 * The caller's roles in `tenant` from the memberships claim: an object of
 * tenant id to role (the `tenant` module's hook), or a list of
 * `{ scope, id, role | roles }` entries (an authorization provider's hook).
 */
function membershipRoles(
  memberships: unknown,
  tenant: string,
  scope: string | undefined,
): string[] {
  if (isRecord(memberships)) {
    const role = optionalText(memberships[tenant]);
    return role === undefined ? [] : [role];
  }
  if (!Array.isArray(memberships)) return [];
  const entry = memberships.find(
    (item): item is Record<string, unknown> =>
      isRecord(item) &&
      optionalText(item["id"]) === tenant &&
      (scope === undefined
        ? item["within"] === undefined
        : optionalText(item["scope"]) === scope),
  );
  if (!entry) return [];
  const role = optionalText(entry["role"]);
  return [...(role === undefined ? [] : [role]), ...stringsOf(entry["roles"])];
}

/**
 * The evaluation context of a request: the user id as `targetingKey`, the
 * tenant, its plan features (`features` claim) and the caller's roles in it
 * (`memberships` claim, in the `tenant` module's or the list shape, or
 * `options.roles`). Pass it as `context` to `withOpenFeature`.
 */
export function flagContext(
  source: FlagContextSource,
  options: FlagContextOptions = {},
): RequestFlagContext {
  const claims = source.jwtClaims ?? {};
  const appMetadata = isRecord(claims["app_metadata"])
    ? claims["app_metadata"]
    : {};
  const tenantClaim = options.tenantClaim ?? "tenant_id";
  const tenant =
    source.tenant ??
    optionalText(claims[tenantClaim]) ??
    optionalText(appMetadata[tenantClaim]);
  const sub = optionalText(claims["sub"]);
  const features = claims[options.featuresClaim ?? "features"];
  const memberships = claims[options.membershipsClaim ?? "memberships"];
  const plans =
    tenant !== undefined &&
    isRecord(features) &&
    Array.isArray(features[tenant])
      ? [...stringsOf(features[tenant])]
      : undefined;
  const resolved =
    tenant === undefined
      ? undefined
      : options.roles
        ? options.roles(claims, tenant)
        : membershipRoles(memberships, tenant, options.membershipScope);
  const roles =
    resolved === undefined
      ? []
      : typeof resolved === "string"
        ? [resolved]
        : [...resolved];
  return {
    ...(sub !== undefined && { targetingKey: sub }),
    ...(tenant !== undefined && { tenant }),
    ...(plans !== undefined && { plans }),
    ...(roles.length > 0 && { role: roles[0]! }),
    ...(roles.length > 1 && { roles }),
  };
}
