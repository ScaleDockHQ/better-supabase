import type {
  FlagContext,
  FlagContextOptions,
  FlagDefinition,
  FlagsProvider,
  FlagsProviderOptions,
  FlagType,
  FlagValue,
} from "../blocks/flags/flags.ts";

import {
  createFlagsProvider,
  evaluateFlag,
  flagContext,
} from "../blocks/flags/flags.ts";
import { errorText } from "../core/block-helpers.ts";

/** One Flags SDK entity; Vercel Flags targets it as `<name>.id`. */
export interface FlagsSdkEntity {
  readonly id: string;
}

/** The tenant, with the plan features and roles that rules match. */
export interface FlagsSdkOrganization extends FlagsSdkEntity {
  readonly plans?: readonly string[];
  readonly roles?: readonly string[];
}

/**
 * What `identify` returns: the user, the tenant as `organization`, and each
 * custom context, such as `brand`, as an entity of its own. The same shape
 * works for `vercelAdapter`, so one `identify` serves both adapters.
 */
export interface FlagsSdkEntities {
  readonly user?: FlagsSdkEntity;
  readonly organization?: FlagsSdkOrganization;
  readonly [context: string]: FlagsSdkEntity | FlagsSdkOrganization | undefined;
}

/** The part of the Flags SDK request that `identify` receives. */
export interface FlagsSdkRequest {
  readonly headers: { get(name: string): string | null };
  readonly cookies: {
    get(name: string): { readonly value: string } | undefined;
  };
}

/**
 * Where a flag is managed, for Flags Explorer: a function of the key, or a URL
 * in which `{key}` is replaced by the key.
 */
export type FlagsSdkOrigin = string | ((key: string) => string | undefined);

/** A Flags SDK option: a variant's value, labelled with its name. */
export interface FlagsSdkOption {
  value: FlagValue;
  label: string;
}

/**
 * The shape of a Flags SDK `Adapter` (`flags` 4.2 or later). This package never
 * imports `flags`; a type test checks this shape against the real one.
 */
export interface FlagsSdkAdapter<V, E = FlagsSdkEntities> {
  readonly adapterId: symbol;
  readonly origin?: (key: string) => string | undefined;
  decide(params: {
    readonly key: string;
    readonly entities?: E;
    readonly defaultValue?: unknown;
  }): Promise<V>;
  bulkDecide(params: {
    readonly flags: readonly {
      readonly key: string;
      readonly defaultValue?: unknown;
    }[];
    readonly entities?: E;
  }): Promise<Record<string, V>>;
}

export type BetterSupabaseAdapterOptions = (
  | { readonly provider: FlagsProvider<string> }
  | (FlagsProviderOptions & { readonly provider?: never })
) & {
  /** Where each flag is managed, such as the app's admin page. */
  readonly origin?: FlagsSdkOrigin;
};

/**
 * What `betterSupabaseAdapter()` returns. Pass it as `adapter` by reference or
 * call it; every adapter it makes shares one definitions cache and one
 * `adapterId`, so `evaluate()` decides them in one `bulkDecide`.
 */
export interface BetterSupabaseAdapterFactory {
  <V = FlagValue>(): FlagsSdkAdapter<V>;
  readonly provider: FlagsProvider<string>;
  readonly origin?: FlagsSdkOrigin;
}

function originOf(
  origin: FlagsSdkOrigin | undefined,
  key: string,
): string | undefined {
  return typeof origin === "function"
    ? origin(key)
    : origin?.replaceAll("{key}", encodeURIComponent(key));
}

/** Maps Flags SDK entities to the provider's evaluation context. */
export function flagContextOf(entities?: FlagsSdkEntities): FlagContext {
  const { user, organization, ...rest } = entities ?? {};
  const roles = organization?.roles ?? [];

  const contexts = Object.fromEntries(
    Object.entries(rest).flatMap(([name, entity]) =>
      typeof entity?.id === "string" ? [[name, entity.id]] : [],
    ),
  );

  return {
    ...(typeof user?.id === "string" && { targetingKey: user.id }),
    ...(typeof organization?.id === "string" && { tenant: organization.id }),
    ...(organization?.plans && { plans: organization.plans }),
    ...(roles.length > 0 && { role: roles[0], roles }),
    ...(Object.keys(contexts).length > 0 && { contexts }),
  };
}

/**
 * Whether `value` fits a flag of `type`; an `object` flag holds any JSON object
 * or list.
 */
function fitsType(value: FlagValue, type: FlagType): boolean {
  return type === "object"
    ? typeof value === "object" && value !== null
    : typeof value === type;
}

/**
 * The flag's value for a declaration with `defaultValue`, or `undefined` for
 * the fallback: a missing variant or an unknown type always falls back. A
 * `null` value is served to a declaration whose default is `null` or unset.
 * Otherwise a declaration without a default takes any value, one with a `null`
 * default a value of the flag's type, and any other default a value of its own
 * `typeof`.
 */
async function valueOf(
  flag: FlagDefinition | undefined,
  defaultValue: unknown,
  context: FlagContext,
): Promise<{ readonly value: FlagValue } | undefined> {
  if (!flag || flag.invalidType !== undefined) {
    return undefined;
  }

  const { value, found } = await evaluateFlag(flag, context);

  if (!found) {
    return undefined;
  }

  if (value === null) {
    return defaultValue === null || defaultValue === undefined
      ? { value }
      : undefined;
  }

  if (defaultValue === undefined) {
    return { value };
  }

  if (defaultValue === null) {
    return fitsType(value, flag.type) ? { value } : undefined;
  }

  return typeof value === typeof defaultValue ? { value } : undefined;
}

const why = (flag: FlagDefinition | undefined): string =>
  flag === undefined
    ? "it is missing"
    : flag.invalidType === undefined
      ? "it has no such variant or has another type"
      : `it has the unknown type "${flag.invalidType}"`;

/**
 * A Flags SDK adapter over the `flags` block. It evaluates rules, overrides,
 * custom contexts and rollouts like `flag_evaluation()`, from definitions it
 * caches for `ttl`. A flag that is missing, has an unknown type, has another
 * type than the declaration or fails to load gets the declaration's
 * `defaultValue`; without one, `decide` throws. A variant whose value is `null`
 * is served to a declaration whose `defaultValue` is `null` or unset.
 */
export function betterSupabaseAdapter(
  options: BetterSupabaseAdapterOptions,
): BetterSupabaseAdapterFactory {
  const provider: FlagsProvider<string> =
    options.provider ?? createFlagsProvider(options);

  const adapterId = Symbol("better-supabase");
  const { origin } = options;

  const fallback = <V>(key: string, defaultValue: unknown, why: string): V => {
    if (defaultValue === undefined) {
      throw new Error(`Flag "${key}": ${why}, and it has no defaultValue`);
    }

    // SAFETY: the Flags SDK passes the declaration's defaultValue, a V.
    return defaultValue as V;
  };

  const make = <V = FlagValue>(): FlagsSdkAdapter<V> => ({
    adapterId,
    ...(origin !== undefined && {
      origin: (key: string) => originOf(origin, key),
    }),
    async decide({ key, entities, defaultValue }) {
      let flags: readonly FlagDefinition[];

      try {
        flags = await provider.definitions();
      } catch (error) {
        return fallback<V>(key, defaultValue, errorText(error));
      }

      const flag = flags.find((entry) => entry.key === key);
      const served = await valueOf(flag, defaultValue, flagContextOf(entities));

      // SAFETY: valueOf served a value that fits the declaration's defaultValue.
      return served === undefined
        ? fallback<V>(key, defaultValue, why(flag))
        : (served.value as V);
    },
    async bulkDecide({ flags, entities }) {
      const decided: Record<string, V> = {};
      let definitions: ReadonlyMap<string, FlagDefinition>;

      try {
        definitions = new Map(
          (await provider.definitions()).map((flag) => [flag.key, flag]),
        );
      } catch {
        return decided;
      }

      const context = flagContextOf(entities);

      for (const { key, defaultValue } of flags) {
        const served = await valueOf(
          definitions.get(key),
          defaultValue,
          context,
        );

        if (served !== undefined) {
          // SAFETY: as in decide, valueOf served a value that fits the declaration.
          decided[key] = served.value as V;
        } else if (defaultValue !== undefined) {
          // SAFETY: the Flags SDK passes the declaration's defaultValue, a V.
          decided[key] = defaultValue as V;
        }
      }

      return decided;
    },
  });

  return Object.assign(make, {
    provider,
    ...(origin !== undefined && { origin }),
  });
}

type Claims = Readonly<Record<string, unknown>>;

type MaybePromise<T> = T | Promise<T>;

export interface CreateIdentifyOptions extends FlagContextOptions {
  /**
   * The request's verified JWT claims, such as from `getClaims()`. Read them
   * locally; `identify` runs for every flag and never calls the Auth server.
   */
  readonly claims: (
    request: FlagsSdkRequest,
  ) => MaybePromise<Claims | null | undefined>;
  /** The active tenant when the claims don't carry it, such as from a cookie. */
  readonly tenant?: (
    request: FlagsSdkRequest,
    claims: Claims | null | undefined,
  ) => MaybePromise<string | null | undefined>;
  /**
   * Custom context values, such as the brand from the host. They win over
   * `contextClaims`; `null` leaves one out.
   */
  readonly contexts?: (
    request: FlagsSdkRequest,
    claims: Claims | null | undefined,
  ) => MaybePromise<
    Readonly<Record<string, string | null | undefined>> | undefined
  >;
}

/**
 * An `identify` for `flag()` declarations, built on `flagContext()`. Wrap it in
 * the Flags SDK's `dedupe` so it runs once per request.
 */
export function createIdentify(
  options: CreateIdentifyOptions,
): (request: FlagsSdkRequest) => Promise<FlagsSdkEntities> {
  return async (request) => {
    const claims = await options.claims(request);
    const tenant = await options.tenant?.(request, claims);
    const contexts = await options.contexts?.(request, claims);

    const context = flagContext(
      {
        jwtClaims: claims,
        ...(tenant !== undefined && { tenant }),
        ...(contexts !== undefined && { contexts }),
      },
      options,
    );

    const roles =
      context.roles ??
      (context.role === undefined ? undefined : [context.role]);

    const named = Object.entries(context.contexts ?? {}).filter(
      ([name]) => name !== "user" && name !== "organization",
    );

    return {
      ...(context.targetingKey !== undefined && {
        user: { id: context.targetingKey },
      }),
      ...(context.tenant !== undefined && {
        organization: {
          id: context.tenant,
          ...(context.plans && { plans: context.plans }),
          ...(roles && { roles }),
        },
      }),
      ...Object.fromEntries(named.map(([name, id]) => [name, { id }])),
    };
  };
}

/**
 * A flag's variants as Flags SDK `options`, labelled by variant name. A
 * precomputed flag needs them to list its permutations.
 */
export function flagOptions(
  definition: Pick<FlagDefinition, "variants">,
): FlagsSdkOption[] {
  return Object.entries(definition.variants).map(([label, value]) => ({
    value,
    label,
  }));
}

/** A flag as Flags Explorer describes it. */
export interface FlagsSdkDefinition {
  options: FlagsSdkOption[];
  description?: string;
  origin?: string;
  updatedAt?: number;
}

/** The Flags SDK's `ProviderData`, for `.well-known/vercel/flags`. */
export interface FlagsSdkProviderData {
  definitions: Record<string, FlagsSdkDefinition>;
  hints: { key: string; text: string }[];
}

/**
 * Flags Explorer data for every flag that isn't archived. Pass the adapter
 * factory or `{ provider, origin }`, and combine the result with other
 * providers' data through `mergeProviderData`. A failed load becomes a hint.
 */
export async function getProviderData(options: {
  readonly provider: FlagsProvider<string>;
  readonly origin?: FlagsSdkOrigin;
}): Promise<FlagsSdkProviderData> {
  let flags: readonly FlagDefinition[];

  try {
    flags = await options.provider.definitions();
  } catch (error) {
    return {
      definitions: {},
      hints: [
        {
          key: "better-supabase/load-failed",
          text: `Could not load the flag definitions: ${errorText(error)}`,
        },
      ],
    };
  }

  const definitions: Record<string, FlagsSdkDefinition> = {};
  const hints: FlagsSdkProviderData["hints"] = [];

  for (const flag of flags) {
    if (flag.archived === true) {
      continue;
    }

    if (flag.invalidType !== undefined) {
      hints.push({
        key: "better-supabase/invalid-type",
        text: `Flag "${flag.key}" has the unknown type "${flag.invalidType}", so it always serves its fallback`,
      });
    }

    const origin = originOf(options.origin, flag.key);

    const updatedAt =
      flag.updatedAt === undefined ? Number.NaN : Date.parse(flag.updatedAt);

    definitions[flag.key] = {
      options: flagOptions(flag),
      ...(flag.description !== undefined && { description: flag.description }),
      ...(origin !== undefined && { origin }),
      ...(Number.isFinite(updatedAt) && { updatedAt }),
    };
  }

  return { definitions, hints };
}
