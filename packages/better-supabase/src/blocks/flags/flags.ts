import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { DEFAULT_CLAIMS } from "../../core/claims.ts";
import {
  blockCall,
  DEFAULT_BLOCK_SCHEMA,
  errorText,
  isRecord,
  optionalText,
  recordsOf,
  stringsOf,
  textOf,
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

/**
 * Who a rule or a segment targets: every list that is set must contain the
 * caller's value.
 */
export interface FlagCondition {
  readonly tenants?: readonly string[];
  readonly users?: readonly string[];
  /** Entitlement lookup keys; one match is enough. */
  readonly plans?: readonly string[];
  readonly roles?: readonly string[];
  /**
   * Custom contexts by name, such as `{ brand: ["acme"] }`; every one must
   * match.
   */
  readonly contexts?: Readonly<Record<string, readonly string[]>>;
}

/** A targeting rule: its condition, and the variant it serves on a match. */
export interface FlagRule extends FlagCondition {
  readonly variant: string;
  /**
   * Named segments (`flag_segments`); the caller must be in one of them. A
   * segment that doesn't exist matches no one.
   */
  readonly segments?: readonly string[];
}

/** One variant of a weighted split and its share of the rollout, 0 to 100. */
export interface FlagSplit {
  readonly variant: string;
  readonly weight: number;
}

/** One step of a scheduled rollout: a percentage held for a duration. */
export interface FlagRolloutStep {
  readonly percentage: number;
  readonly durationSeconds: number;
}

/**
 * A rollout that grows on its own: nothing before `startAt`, then each step in
 * turn, then `finalPercentage` (default the last step's percentage).
 */
export interface FlagRolloutSchedule {
  /** An ISO 8601 instant. */
  readonly startAt: string;
  readonly steps: readonly FlagRolloutStep[];
  readonly finalPercentage?: number;
}

/**
 * A variant for one tenant, one user or one custom context value. A user
 * override beats a tenant one, and a tenant one beats a context one; among
 * context overrides, the first in the list wins (`flag_definitions()` lists
 * them in the declared order of `options.contexts`).
 */
export interface FlagOverride {
  readonly organizationId: string | undefined;
  readonly userId: string | undefined;
  /** The custom context, such as `brand`, with `contextKey` its value. */
  readonly context?: string | undefined;
  readonly contextKey?: string | undefined;
  readonly variant: string;
}

/** A row of the `flags` table with its overrides (`flag_definitions()`). */
export interface FlagDefinition {
  readonly key: string;
  /** `"boolean"` when the row's type is unknown; `invalidType` then holds it. */
  readonly type: FlagType;
  /**
   * The row's type when it isn't one of `FlagType`. Such a flag is never
   * served: the adapters fall back and the provider reports `PARSE_ERROR`.
   */
  readonly invalidType?: string;
  readonly description?: string;
  readonly variants: Readonly<Record<string, FlagValue>>;
  readonly defaultVariant: string;
  readonly enabled: boolean;
  /**
   * An archived flag serves its default variant and is hidden from Flags
   * Explorer.
   */
  readonly archived?: boolean;
  readonly rules: readonly FlagRule[];
  /**
   * The share of targets in the rollout, 0 to 100 in steps of 0.01; a
   * `rolloutSchedule` replaces it.
   */
  readonly rolloutPercentage: number;
  /**
   * How the rollout splits between variants. Weights that add up to less than
   * 100 leave the rest on the default variant.
   */
  readonly rolloutVariants: readonly FlagSplit[];
  readonly rolloutSchedule?: FlagRolloutSchedule;
  readonly overrides: readonly FlagOverride[];
  /**
   * The segments the rules name, by name (`flag_definitions()` includes only
   * those).
   */
  readonly segments?: Readonly<Record<string, FlagCondition>>;
  /** When the flag was created, as an ISO 8601 string. */
  readonly createdAt?: string;
  /** When the flag last changed, as an ISO 8601 string. */
  readonly updatedAt?: string;
  /**
   * The extra columns (`blocks['flags'].options.extraColumns`), when the flag
   * has any.
   */
  readonly fields?: Readonly<Record<string, unknown>>;
}

/**
 * The OpenFeature evaluation context the provider reads. `targetingKey` is the
 * user id; without one, the rollout buckets by `tenant`.
 */
export interface FlagContext {
  readonly targetingKey?: string;
  readonly tenant?: string;
  readonly plans?: readonly string[];
  readonly role?: string;
  /**
   * Every role the caller holds in the tenant; a `roles` rule matches any of
   * them.
   */
  readonly roles?: readonly string[];
  /**
   * Custom context values by name, such as `{ brand: "acme" }`. Unlike
   * `flag_evaluation()`, the provider never reads them from the tenant.
   */
  readonly contexts?: Readonly<Record<string, string>>;
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
  contexts?: Record<string, string>;
};

export type FlagReason =
  | "DISABLED"
  | "OVERRIDE"
  | "TARGETING_MATCH"
  | "SPLIT"
  | "DEFAULT"
  | "ERROR";

export type FlagErrorCode =
  | "FLAG_NOT_FOUND"
  | "TYPE_MISMATCH"
  | "PARSE_ERROR"
  | "PROVIDER_NOT_READY"
  | "GENERAL";

/**
 * The shape of an OpenFeature `ResolutionDetails`. `Code` is the type of
 * `errorCode`: OpenFeature's `ErrorCode` when `errorCodes: ErrorCode` is passed
 * to the provider, the matching string literals otherwise.
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
 * The rollout bucket of `target` for `flag`, 0 to 9999: the first 32 bits of
 * SHA-256(`flag.target`) modulo 10000. `better_supabase.flag_bucket()` computes
 * the same number, so SQL and TypeScript agree on who is in.
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

function conditionMatches(rule: FlagCondition, context: FlagContext): boolean {
  return (
    contains(rule.tenants, context.tenant) &&
    contains(rule.users, context.targetingKey) &&
    anyIn(rule.roles, [
      ...(context.role === undefined ? [] : [context.role]),
      ...(context.roles ?? []),
    ]) &&
    (rule.plans === undefined ||
      rule.plans.some((plan) => context.plans?.includes(plan) === true)) &&
    (rule.contexts === undefined ||
      Object.entries(rule.contexts).every(([name, keys]) =>
        contains(keys, context.contexts?.[name]),
      ))
  );
}

/**
 * The conditions of the segments `rule` names, from `segments`; a name with no
 * segment drops out. A rule with `segments` matches a caller in one of them.
 */
export function expandSegments(
  rule: Pick<FlagRule, "segments">,
  segments: Readonly<Record<string, FlagCondition>> = {},
): readonly FlagCondition[] {
  return (rule.segments ?? []).flatMap((name) => {
    const segment = Object.hasOwn(segments, name) ? segments[name] : undefined;

    return segment === undefined ? [] : [segment];
  });
}

function ruleMatches(
  rule: FlagRule,
  context: FlagContext,
  segments: FlagDefinition["segments"],
): boolean {
  return (
    conditionMatches(rule, context) &&
    (rule.segments === undefined ||
      expandSegments(rule, segments).some((segment) =>
        conditionMatches(segment, context),
      ))
  );
}

/**
 * The rollout percentage of `schedule` at `nowMs`: 0 before `startAt`, then
 * each step's percentage for its duration, then `finalPercentage` (default the
 * last step's). `flag_evaluation()` computes the same number.
 */
export function rolloutPercentageAt(
  schedule: FlagRolloutSchedule,
  nowMs: number,
): number {
  const start = Date.parse(schedule.startAt);

  if (!Number.isFinite(start) || nowMs < start) {
    return 0;
  }

  let elapsed = (nowMs - start) / 1000;

  for (const step of schedule.steps) {
    if (elapsed < step.durationSeconds) {
      return step.percentage;
    }

    elapsed -= step.durationSeconds;
  }

  return schedule.finalPercentage ?? schedule.steps.at(-1)?.percentage ?? 0;
}

/**
 * The variant of `splits` that `bucket` (0 to 9999) falls in, by cumulative
 * weight; `undefined` past the last one, which serves the default variant.
 */
export function chooseSplitVariant(
  bucket: number,
  splits: readonly FlagSplit[],
): string | undefined {
  let edge = 0;

  for (const split of splits) {
    edge += split.weight * 100;

    if (bucket < edge) {
      return split.variant;
    }
  }

  return undefined;
}

/** The effective rollout percentage of `flag` at `nowMs`. */
const percentageOf = (flag: FlagDefinition, nowMs: number): number =>
  flag.rolloutSchedule === undefined
    ? flag.rolloutPercentage
    : rolloutPercentageAt(flag.rolloutSchedule, nowMs);

async function chooseVariant(
  flag: FlagDefinition,
  context: FlagContext,
  nowMs: number,
): Promise<{ variant: string; reason: FlagReason }> {
  if (!flag.enabled || flag.archived === true) {
    return { variant: flag.defaultVariant, reason: "DISABLED" };
  }

  const override =
    flag.overrides.find(
      (entry) =>
        entry.userId !== undefined && entry.userId === context.targetingKey,
    ) ??
    flag.overrides.find(
      (entry) =>
        entry.organizationId !== undefined &&
        entry.organizationId === context.tenant,
    ) ??
    flag.overrides.find(
      (entry) =>
        entry.context !== undefined &&
        entry.contextKey !== undefined &&
        entry.contextKey === context.contexts?.[entry.context],
    );

  let chosen = override?.variant;
  let reason: FlagReason = chosen === undefined ? "DEFAULT" : "TARGETING_MATCH";

  if (chosen === undefined) {
    const rule = flag.rules.find((entry) =>
      ruleMatches(entry, context, flag.segments),
    );

    if (rule) {
      chosen = rule.variant;
      reason = "TARGETING_MATCH";
    }
  }

  const target = context.targetingKey ?? context.tenant;

  if (
    chosen === undefined &&
    flag.rolloutVariants.length > 0 &&
    target !== undefined &&
    (await flagBucket(flag.key, target)) < percentageOf(flag, nowMs) * 100
  ) {
    // A second bucket, so growing the rollout never moves a target between
    // variants.
    chosen = chooseSplitVariant(
      await flagBucket(`${flag.key}/split`, target),
      flag.rolloutVariants,
    );
    reason = "SPLIT";
  }

  if (chosen === undefined || !Object.hasOwn(flag.variants, chosen)) {
    return { variant: flag.defaultVariant, reason: "DEFAULT" };
  }

  return { variant: chosen, reason };
}

/** The result of `evaluateFlag()`, which never fails. */
export interface FlagEvaluation {
  /** The variant's value; `null` when `found` is false. */
  readonly value: FlagValue;
  readonly variant: string;
  readonly reason: FlagReason;
  /** Whether `variants` has the chosen variant, so a `null` value is real. */
  readonly found: boolean;
}

export interface EvaluateFlagOptions {
  /** The time a `rolloutSchedule` is read at, in milliseconds. Default now. */
  readonly now?: number;
}

/** Evaluates one flag as `better_supabase.flag_evaluation()` does. */
export async function evaluateFlag(
  flag: FlagDefinition,
  context: FlagContext = {},
  options: EvaluateFlagOptions = {},
): Promise<FlagEvaluation> {
  const { variant, reason } = await chooseVariant(
    flag,
    context,
    options.now ?? Date.now(),
  );

  const found = Object.hasOwn(flag.variants, variant);

  return {
    value: found ? (flag.variants[variant] ?? null) : null,
    variant,
    reason,
    found,
  };
}

const FLAG_TYPES: ReadonlySet<string> = new Set([
  "boolean",
  "string",
  "number",
  "object",
]);

const flagTypeOf = (
  value: unknown,
): Pick<FlagDefinition, "type" | "invalidType"> => {
  const text = textOf(value);

  if (value === undefined || value === null || FLAG_TYPES.has(text)) {
    // SAFETY: checked against the types the flags table's check allows.
    return { type: FLAG_TYPES.has(text) ? (text as FlagType) : "boolean" };
  }

  return { type: "boolean", invalidType: text };
};

const listOf = (
  value: Readonly<Record<string, unknown>>,
  key: string,
): readonly string[] | undefined =>
  Array.isArray(value[key]) ? stringsOf(value[key]) : undefined;

/** Parses a rule's or a segment's condition. */
export function conditionOf(
  value: Readonly<Record<string, unknown>>,
): FlagCondition {
  const tenants = listOf(value, "tenants");
  const users = listOf(value, "users");
  const plans = listOf(value, "plans");
  const roles = listOf(value, "roles");
  const raw = value["contexts"];

  const contexts = isRecord(raw)
    ? Object.fromEntries(
        Object.entries(raw).map(([name, keys]) => [
          name,
          Array.isArray(keys) ? stringsOf(keys) : [],
        ]),
      )
    : undefined;

  return {
    ...(tenants && { tenants }),
    ...(users && { users }),
    ...(plans && { plans }),
    ...(roles && { roles }),
    ...(contexts && { contexts }),
  };
}

function ruleOf(value: unknown): FlagRule | undefined {
  if (!isRecord(value) || typeof value["variant"] !== "string") {
    return undefined;
  }

  const segments = listOf(value, "segments");

  return {
    variant: value["variant"],
    ...conditionOf(value),
    ...(segments && { segments }),
  };
}

function splitsOf(value: unknown): readonly FlagSplit[] {
  return (Array.isArray(value) ? value : []).flatMap((entry) =>
    isRecord(entry) && typeof entry["variant"] === "string"
      ? [{ variant: entry["variant"], weight: Number(entry["weight"] ?? 0) }]
      : [],
  );
}

function scheduleOf(value: unknown): FlagRolloutSchedule | undefined {
  if (!isRecord(value) || typeof value["startAt"] !== "string") {
    return undefined;
  }

  const steps = (Array.isArray(value["steps"]) ? value["steps"] : []).flatMap(
    (step) =>
      isRecord(step)
        ? [
            {
              percentage: Number(step["percentage"] ?? 0),
              durationSeconds: Number(step["durationSeconds"] ?? 0),
            },
          ]
        : [],
  );

  const final = value["finalPercentage"];

  return {
    startAt: value["startAt"],
    steps,
    ...(typeof final === "number" && { finalPercentage: final }),
  };
}

function segmentsOf(
  value: unknown,
): Readonly<Record<string, FlagCondition>> | undefined {
  if (!isRecord(value) || Object.keys(value).length === 0) {
    return undefined;
  }

  return Object.fromEntries(
    Object.entries(value).map(([name, condition]) => [
      name,
      isRecord(condition) ? conditionOf(condition) : {},
    ]),
  );
}

const withValue = <K extends string, V>(
  key: K,
  value: V | undefined,
): Partial<Record<K, V>> =>
  // SAFETY: one entry under key, present only when value is.
  (value === undefined ? {} : { [key]: value }) as Partial<Record<K, V>>;

/** Parses the rows of `flag_definitions()`. */
export function flagDefinitionsOf(value: unknown): readonly FlagDefinition[] {
  return recordsOf(value, "flag_definitions").map((row) => ({
    key: textOf(row["key"]),
    ...flagTypeOf(row["type"]),
    // SAFETY: a jsonb object column; its values are JSON.
    variants: (isRecord(row["variants"]) ? row["variants"] : {}) as Record<
      string,
      FlagValue
    >,
    defaultVariant: optionalText(row["default_variant"]) ?? "",
    ...(optionalText(row["description"]) !== undefined && {
      description: textOf(row["description"]),
    }),
    enabled: row["enabled"] !== false,
    ...(row["archived"] === true && { archived: true }),
    rules: (Array.isArray(row["rules"]) ? row["rules"] : []).flatMap((rule) => {
      const parsed = ruleOf(rule);

      return parsed ? [parsed] : [];
    }),
    rolloutPercentage: Number(row["rollout_percentage"] ?? 0),
    rolloutVariants: splitsOf(row["rollout_variants"]),
    ...withValue("rolloutSchedule", scheduleOf(row["rollout_schedule"])),
    overrides: recordsOf(row["overrides"] ?? [], "flag_definitions").map(
      overrideOf,
    ),
    ...withValue("segments", segmentsOf(row["segments"])),
    ...(optionalText(row["created_at"]) !== undefined && {
      createdAt: textOf(row["created_at"]),
    }),
    ...(optionalText(row["updated_at"]) !== undefined && {
      updatedAt: textOf(row["updated_at"]),
    }),
    ...(isRecord(row["fields"]) ? { fields: row["fields"] } : {}),
  }));
}

function overrideOf(entry: Readonly<Record<string, unknown>>): FlagOverride {
  const context = optionalText(entry["context"]);
  const contextKey = optionalText(entry["context_key"]);

  return {
    organizationId: optionalText(entry["organization_id"]),
    userId: optionalText(entry["user_id"]),
    ...(context !== undefined && { context }),
    ...(contextKey !== undefined && { contextKey }),
    variant: textOf(entry["variant"]),
  };
}

export interface FlagsProviderOptions<
  Code extends string = FlagErrorCode,
> extends BlockTemporalOptions {
  /**
   * A service-role transport: `flag_definitions()` is granted to `service_role`
   * only, as it lists every override.
   */
  readonly transport?: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  /** Error mappers that run before the built-in ones. */
  readonly mappers?: readonly ErrorMapper[];
  /** How long the definitions are cached, in milliseconds. Default 30000. */
  readonly ttl?: number;
  /** Fixed definitions instead of a transport, for tests and static flags. */
  readonly definitions?: readonly FlagDefinition[];
  /**
   * OpenFeature's `ErrorCode` enum (from `@openfeature/core` or
   * `@openfeature/server-sdk`), so the provider's types match `Provider`. A map
   * without `PARSE_ERROR` reports an unknown flag type as `GENERAL`.
   */
  readonly errorCodes?: Readonly<
    Record<Exclude<FlagErrorCode, "PARSE_ERROR">, Code> &
      Partial<Record<"PARSE_ERROR", Code>>
  >;
  readonly now?: () => number;
  /**
   * Runs after every evaluation, such as `reportValue` from `flags` for Web
   * Analytics. It can't change the result; an error it throws is dropped.
   */
  readonly onEvaluate?: (
    key: string,
    value: FlagValue,
    details: FlagResolution<FlagValue, Code>,
  ) => void;
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
  /**
   * Every definition, from the same cache as the evaluations. It rejects when
   * the definitions fail to load.
   */
  definitions(): Promise<readonly FlagDefinition[]>;
  /** Drops the cache, so the next evaluation reloads the definitions. */
  refresh(): void;
}

const DEFAULT_CODES: Readonly<Record<FlagErrorCode, FlagErrorCode>> = {
  FLAG_NOT_FOUND: "FLAG_NOT_FOUND",
  TYPE_MISMATCH: "TYPE_MISMATCH",
  PARSE_ERROR: "PARSE_ERROR",
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

  const call =
    transport === undefined
      ? undefined
      : blockCall(
          transport,
          options.schema ?? DEFAULT_BLOCK_SCHEMA,
          options.mappers,
        );

  const fetchFlags = definitions
    ? () => Promise.resolve(definitions)
    : call
      ? () => call("flag_definitions", {}, flagDefinitionsOf).orThrow()
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
    if (cache && now() - cache.at < ttl) {
      return cache.flags;
    }

    const flags = fetchFlags().then(
      (list) => new Map(list.map((flag) => [flag.key, flag])),
    );

    const entry = { at: now(), flags };
    cache = entry;
    flags.catch(() => {
      if (cache === entry) {
        cache = undefined;
      }
    });

    return flags;
  };

  async function resolve<T extends FlagValue>(
    flagKey: string,
    defaultValue: T,
    context: FlagContext,
    check: (value: FlagValue) => value is T,
  ): Promise<FlagResolution<T, Code>> {
    const resolution = await decide(flagKey, defaultValue, context, check);

    try {
      options.onEvaluate?.(flagKey, resolution.value, resolution);
    } catch {
      // A reporting hook never changes the result.
    }

    return resolution;
  }

  async function decide<T extends FlagValue>(
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

    if (flag.invalidType !== undefined) {
      return {
        value: defaultValue,
        reason: "ERROR",
        errorCode: codes.PARSE_ERROR ?? codes.GENERAL,
        errorMessage: `Flag "${flagKey}" has the unknown type "${flag.invalidType}"`,
      };
    }

    const result = await evaluateFlag(flag, context, { now: now() });

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
    definitions: async () => [...(await load()).values()],
    refresh() {
      cache = undefined;
    },
  };
}

/**
 * The four `get*Details` methods that the OpenFeature server `Client` and the
 * `FlagClient` of `@supabase-labs/middleware-openfeature` share.
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
 * A flag client without the OpenFeature SDK: `withOpenFeature({ client })` from
 * `@supabase-labs/middleware-openfeature` accepts it.
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
  /**
   * Custom context values the request carries, such as the brand from the host.
   * They win over `options.contextClaims`; `null` leaves one out.
   */
  readonly contexts?: Readonly<Record<string, string | null | undefined>>;
}

export interface FlagContextOptions {
  /** `config.claims.tenant`, default `tenant_id`. */
  readonly tenantClaim?: string;
  /** `config.claims.features`, default `features`. */
  readonly featuresClaim?: string;
  /** The claim the memberships hook writes, default `memberships`. */
  readonly membershipsClaim?: string;
  /**
   * The scope of tenant memberships when the claim is a list of entries, as an
   * authorization provider's hook may write it (`{ scope, id, roles }`).
   * Without it, the entry for the tenant id that has no `within` (a root scope)
   * is read.
   */
  readonly membershipScope?: string;
  /** Reads the caller's roles in `tenant` from claims of another shape. */
  readonly roles?: (
    claims: Readonly<Record<string, unknown>>,
    tenant: string,
  ) => string | readonly string[] | undefined;
  /**
   * Custom contexts read from claims: a context name to the claim that holds
   * it, such as `{ brand: "brand_id" }`. A claim is read from the top level,
   * then from `app_metadata`.
   */
  readonly contextClaims?: Readonly<Record<string, string>>;
}

/**
 * The caller's roles in `tenant` from the memberships claim: an object of
 * tenant id to role (the `tenant` module's hook), or a list of `{ scope, id,
 * role | roles }` entries (an authorization provider's hook).
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

  if (!Array.isArray(memberships)) {
    return [];
  }

  const entry = memberships.find(
    (item): item is Record<string, unknown> =>
      isRecord(item) &&
      optionalText(item["id"]) === tenant &&
      (scope === undefined
        ? item["within"] === undefined
        : optionalText(item["scope"]) === scope),
  );

  if (!entry) {
    return [];
  }

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

  const tenantClaim = options.tenantClaim ?? DEFAULT_CLAIMS.tenant;

  const tenant =
    source.tenant ??
    optionalText(claims[tenantClaim]) ??
    optionalText(appMetadata[tenantClaim]);

  const sub = optionalText(claims["sub"]);
  const features = claims[options.featuresClaim ?? DEFAULT_CLAIMS.features];

  const memberships =
    claims[options.membershipsClaim ?? DEFAULT_CLAIMS.memberships];

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

  const contexts = new Map<string, string>();

  for (const [name, claim] of Object.entries(options.contextClaims ?? {})) {
    const value =
      optionalText(claims[claim]) ?? optionalText(appMetadata[claim]);

    if (value !== undefined) {
      contexts.set(name, value);
    }
  }

  for (const [name, value] of Object.entries(source.contexts ?? {})) {
    if (typeof value === "string") {
      contexts.set(name, value);
    } else {
      contexts.delete(name);
    }
  }

  return {
    ...(sub !== undefined && { targetingKey: sub }),
    ...(tenant !== undefined && { tenant }),
    ...(plans !== undefined && { plans }),
    ...(roles.length > 0 && { role: roles[0]! }),
    ...(roles.length > 1 && { roles }),
    ...(contexts.size > 0 && { contexts: Object.fromEntries(contexts) }),
  };
}
