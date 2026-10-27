import { getEnv } from "@supabase/middleware";

import type { AuthState } from "../auth/resolve.ts";
import type {
  FlagContext,
  FlagContextOptions,
  FlagDefinition,
  FlagResolution,
  FlagsProvider,
  FlagsProviderOptions,
  FlagType,
  FlagValue,
} from "../blocks/flags/flags.ts";
import type { BlockTransport } from "../core/block-transport.ts";

import { jwtClaimsOf } from "../auth/claims.ts";
import {
  createFlagsProvider,
  evaluateFlag,
  flagContext,
} from "../blocks/flags/flags.ts";
import { errorText } from "../core/block-helpers.ts";
import { FLAG_OVERRIDES_COOKIE } from "./cookie.ts";

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
  /** A signed-out visitor's stable id, such as from a cookie. */
  readonly visitor?: FlagsSdkEntity;
  readonly [context: string]: FlagsSdkEntity | FlagsSdkOrganization | undefined;
}

/** The part of the Flags SDK request that `identify` receives. */
export interface FlagsSdkRequest {
  readonly headers: { get(name: string): string | null };
  readonly cookies: {
    get(name: string): { readonly value: string } | undefined;
    getAll?(): readonly { readonly name: string; readonly value: string }[];
  };
}

/**
 * Where a flag is managed, for Flags Explorer: a URL in which `{key}` is
 * replaced by the key, an origin object such as `{ provider: "vercel",
 * projectId }`, or a function of the key returning either.
 */
export type FlagsSdkOrigin =
  | string
  | FlagsSdkOriginObject
  | ((key: string) => string | FlagsSdkOriginObject | undefined);

/** A Flags SDK `Origin` object; Flags Explorer links it to its provider. */
export type FlagsSdkOriginObject = Readonly<Record<string, unknown>>;

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
  readonly origin?: (key: string) => string | FlagsSdkOriginObject | undefined;
  readonly identify?: (request: FlagsSdkRequest) => MaybePromise<E | undefined>;
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

/**
 * The project's URL and secret key, for a server that has no supabase-js client
 * at hand. The definitions load over the Data API.
 */
export interface FlagsSdkProjectOptions {
  readonly url: string;
  /** A secret key (`sb_secret_...`) or a legacy `service_role` key. */
  readonly secretKey: string;
  /**
   * The schema `flag_definitions()` is reached through, such as the API schema
   * from `blocks.flags.api`. Default `better_supabase`.
   */
  readonly schema?: string;
  /** How long the definitions are cached, in milliseconds. Default 30000. */
  readonly ttl?: number;
  /** The `fetch` the calls go through. Default the global one. */
  readonly fetch?: (url: string, init: RequestInit) => Promise<Response>;
}

export type BetterSupabaseAdapterOptions = (
  | { readonly provider: FlagsProvider<string>; readonly url?: never }
  | (FlagsProviderOptions & { readonly provider?: never; readonly url?: never })
  | (FlagsSdkProjectOptions & { readonly provider?: never })
) & {
  /** Where each flag is managed, such as the app's admin page. */
  readonly origin?: FlagsSdkOrigin;
  /**
   * The entities every flag of this adapter is decided for, such as
   * `dedupe(createIdentify({ server }))`. A declaration's own `identify` wins.
   */
  readonly identify?: (
    request: FlagsSdkRequest,
  ) => MaybePromise<FlagsSdkEntities | undefined>;
};

/**
 * What `createBetterSupabaseAdapter()` returns. Pass it as `adapter` by
 * reference or call it; every adapter it makes shares one definitions cache,
 * one `identify` and one `adapterId`, so `evaluate()` decides them in one
 * `bulkDecide`.
 */
export interface BetterSupabaseAdapterFactory {
  <V = FlagValue>(): FlagsSdkAdapter<V>;
  /** The provider, built on first use; reading it throws when it can't be. */
  readonly provider: FlagsProvider<string>;
  readonly origin?: FlagsSdkOrigin;
}

function originOf(
  origin: FlagsSdkOrigin | undefined,
  key: string,
): string | FlagsSdkOriginObject | undefined {
  if (typeof origin === "function") {
    return origin(key);
  }

  return typeof origin === "string"
    ? origin.replaceAll("{key}", encodeURIComponent(key))
    : origin;
}

/**
 * Maps Flags SDK entities to the provider's evaluation context. A signed-out
 * request's `visitor` is the targeting key, so rollouts stay stable for it.
 */
export function flagContextOf(entities?: FlagsSdkEntities): FlagContext {
  const { user, organization, visitor, ...rest } = entities ?? {};
  const roles = organization?.roles ?? [];
  const targetingKey = user?.id ?? visitor?.id;

  const contexts = Object.fromEntries(
    Object.entries(rest).flatMap(([name, entity]) =>
      typeof entity?.id === "string" ? [[name, entity.id]] : [],
    ),
  );

  return {
    ...(typeof targetingKey === "string" && { targetingKey }),
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

/** `flag_definitions()` and friends over the Data API, with a secret key. */
function projectTransport(options: FlagsSdkProjectOptions): BlockTransport {
  const base = options.url.replace(/\/+$/, "");
  const request = options.fetch ?? ((url, init) => fetch(url, init));

  // A legacy service_role key is a JWT; a secret key is only an apikey.
  const authorization = options.secretKey.startsWith("sb_")
    ? {}
    : { authorization: `Bearer ${options.secretKey}` };

  return {
    async call(schema, fn, args) {
      const response = await request(
        `${base}/rest/v1/rpc/${encodeURIComponent(fn)}`,
        {
          method: "POST",
          headers: {
            apikey: options.secretKey,
            ...authorization,
            "content-type": "application/json",
            "content-profile": schema,
            "accept-profile": schema,
          },
          body: JSON.stringify(args),
        },
      );

      const body: unknown = await response.json().catch(() => null);

      if (!response.ok) {
        const message =
          typeof body === "object" && body !== null && "message" in body
            ? String(body.message)
            : `${fn} answered ${response.status}`;

        throw Object.assign(new Error(message), body);
      }

      return body;
    },
  };
}

function providerOf(
  options: BetterSupabaseAdapterOptions,
): FlagsProvider<string> {
  if (options.provider !== undefined) {
    return options.provider;
  }

  if (options.url !== undefined) {
    return createFlagsProvider({
      transport: projectTransport(options),
      ...(options.schema !== undefined && { schema: options.schema }),
      ...(options.ttl !== undefined && { ttl: options.ttl }),
    });
  }

  return createFlagsProvider(options);
}

/**
 * A Flags SDK adapter over the `flags` block. It evaluates rules, overrides,
 * custom contexts and rollouts like `flag_evaluation()`, from definitions it
 * caches for `ttl`. A flag that is missing, has an unknown type, has another
 * type than the declaration or fails to load gets the declaration's
 * `defaultValue`; without one, `decide` throws. A variant whose value is `null`
 * is served to a declaration whose `defaultValue` is `null` or unset. Without
 * options it reads `SUPABASE_URL` (or `NEXT_PUBLIC_SUPABASE_URL`) and
 * `SUPABASE_SECRET_KEY` on first use.
 */
export function createBetterSupabaseAdapter(
  options?: BetterSupabaseAdapterOptions,
): BetterSupabaseAdapterFactory {
  let built: FlagsProvider<string> | undefined;

  const lazy = (): FlagsProvider<string> => {
    built ??= providerOf(options ?? envOptions());

    return built;
  };

  const adapterId = Symbol("better-supabase");
  const origin = options?.origin;
  const identify = options?.identify;

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
    ...(identify !== undefined && { identify }),
    async decide({ key, entities, defaultValue }) {
      let flags: readonly FlagDefinition[];

      try {
        flags = await lazy().definitions();
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
          (await lazy().definitions()).map((flag) => [flag.key, flag]),
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

  // SAFETY: the properties defined here are the ones the factory type adds.
  return Object.defineProperties(make, {
    provider: { enumerable: true, get: lazy },
    ...(origin !== undefined && {
      origin: { enumerable: true, value: origin },
    }),
  }) as BetterSupabaseAdapterFactory;
}

/** The default adapter's options, from the runtime's environment. */
function envOptions(): FlagsSdkProjectOptions {
  const url = getEnv("SUPABASE_URL") ?? getEnv("NEXT_PUBLIC_SUPABASE_URL");
  const secretKey = getEnv("SUPABASE_SECRET_KEY");

  if (!url || !secretKey) {
    throw new Error(
      "betterSupabaseAdapter needs SUPABASE_URL (or NEXT_PUBLIC_SUPABASE_URL) and SUPABASE_SECRET_KEY; pass options to createBetterSupabaseAdapter() otherwise",
    );
  }

  return { url, secretKey };
}

/**
 * The adapter from the environment, like the Flags SDK's own adapters: `flag({
 * key, adapter: betterSupabaseAdapter, defaultValue })`. It reads the variables
 * on first use, so importing it never throws.
 */
export const betterSupabaseAdapter: BetterSupabaseAdapterFactory =
  /* @__PURE__ */ createBetterSupabaseAdapter();

type Claims = Readonly<Record<string, unknown>>;

type MaybePromise<T> = T | Promise<T>;

/**
 * The part of a better-supabase server `createIdentify` reads the claims
 * through: `createServer`, `createNext` and the other adapters all have it.
 */
export interface FlagsSdkServer {
  resolve(
    request: Request,
    options?: { readonly refresh?: boolean },
  ): Promise<{ readonly auth: AuthState }>;
}

interface IdentifyHooks extends FlagContextOptions {
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
  /**
   * A signed-out visitor's stable id, such as a cookie the proxy sets. It
   * becomes the `visitor` entity and the targeting key, so a percentage rollout
   * serves a visitor the same variant on every request.
   */
  readonly visitor?: (
    request: FlagsSdkRequest,
  ) => MaybePromise<string | null | undefined>;
}

export type CreateIdentifyOptions = IdentifyHooks &
  (
    | {
        /**
         * The server whose `resolve` verifies the request's token locally;
         * `identify` never calls the Auth server.
         */
        readonly server: FlagsSdkServer;
        readonly claims?: never;
      }
    | {
        /**
         * The request's verified JWT claims, such as from `getClaims()`. Read
         * them locally; `identify` runs for every flag and never calls the Auth
         * server.
         */
        readonly claims: (
          request: FlagsSdkRequest,
        ) => MaybePromise<Claims | null | undefined>;
        readonly server?: never;
      }
  );

/** The request `resolve` needs, from the headers the Flags SDK passes. */
function requestOf({ headers, cookies }: FlagsSdkRequest): Request {
  const forwarded = new Headers();

  for (const name of ["cookie", "authorization"]) {
    const value = headers.get(name);

    if (value !== null) {
      forwarded.set(name, value);
    }
  }

  // Some callers pass cookies without a cookie header, such as `.run()`.
  if (!forwarded.has("cookie")) {
    const all = cookies.getAll?.() ?? [];

    if (all.length > 0) {
      forwarded.set(
        "cookie",
        all.map(({ name, value }) => `${name}=${value}`).join("; "),
      );
    }
  }

  return new Request("https://flags.invalid/", { headers: forwarded });
}

/**
 * An `identify` for `flag()` declarations or the adapter, built on
 * `flagContext()`. Wrap it in the Flags SDK's `dedupe` so it runs once per
 * request.
 */
export function createIdentify(
  options: CreateIdentifyOptions,
): (request: FlagsSdkRequest) => Promise<FlagsSdkEntities> {
  const { server } = options;

  const claimsOf =
    server === undefined
      ? options.claims
      : async (request: FlagsSdkRequest) =>
          jwtClaimsOf(
            (await server.resolve(requestOf(request), { refresh: false })).auth,
          );

  return async (request) => {
    const claims = await claimsOf(request);
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

    const visitor =
      context.targetingKey === undefined
        ? await options.visitor?.(request)
        : undefined;

    const roles =
      context.roles ??
      (context.role === undefined ? undefined : [context.role]);

    const named = Object.entries(context.contexts ?? {}).filter(
      ([name]) =>
        name !== "user" && name !== "organization" && name !== "visitor",
    );

    return {
      ...(context.targetingKey !== undefined && {
        user: { id: context.targetingKey },
      }),
      ...(typeof visitor === "string" &&
        visitor !== "" && { visitor: { id: visitor } }),
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
  /** Stored variants labelled by name, else the declaration's options. */
  options: { value: unknown; label?: string }[];
  description?: string;
  origin?: string | FlagsSdkOriginObject;
  /** `true` for a flag a `flag()` declaration names, else `false`. */
  declaredInCode?: boolean;
  /**
   * The declaration's `defaultValue`, served when the flag can't load; for a
   * flag only the table has, its default variant's value.
   */
  defaultValue?: unknown;
  /** In milliseconds since the epoch. */
  createdAt?: number;
  /** In milliseconds since the epoch. */
  updatedAt?: number;
}

const millisOf = (instant: string | undefined): number | undefined => {
  const value = instant === undefined ? Number.NaN : Date.parse(instant);

  return Number.isFinite(value) ? value : undefined;
};

/**
 * One stored flag as Flags Explorer describes it: its variants as options, its
 * default variant's value, where it is managed and when it changed. It isn't
 * `declaredInCode` until `getProviderData` joins a declaration.
 */
export function toFlagsSdkDefinition(
  flag: FlagDefinition,
  origin?: FlagsSdkOrigin,
): FlagsSdkDefinition {
  const where = originOf(origin, flag.key);
  const createdAt = millisOf(flag.createdAt);
  const updatedAt = millisOf(flag.updatedAt);

  return {
    options: flagOptions(flag),
    ...(flag.description !== undefined && { description: flag.description }),
    ...(where !== undefined && { origin: where }),
    declaredInCode: false,
    ...(Object.hasOwn(flag.variants, flag.defaultVariant) && {
      defaultValue: flag.variants[flag.defaultVariant],
    }),
    ...(createdAt !== undefined && { createdAt }),
    ...(updatedAt !== undefined && { updatedAt }),
  };
}

/** The variants of `flag` whose value doesn't fit its type. */
function misfits(flag: FlagDefinition): readonly string[] {
  return flag.invalidType === undefined
    ? Object.entries(flag.variants)
        .filter(([, value]) => value !== null && !fitsType(value, flag.type))
        .map(([name]) => name)
    : [];
}

/** How the declared flags and the stored ones differ, by key. */
export interface FlagDrift {
  /** Declared in code but missing from the table: they serve `defaultValue`. */
  readonly notStored: readonly string[];
  /** In the table but declared nowhere: candidates to archive. */
  readonly notDeclared: readonly string[];
}

/** Compares the declared flag keys with the stored, unarchived ones. */
export function flagDrift(
  declared: readonly Pick<FlagsSdkDeclaredFlag, "key">[],
  stored: readonly Pick<FlagDefinition, "key" | "archived">[],
): FlagDrift {
  const declaredKeys = new Set(declared.map((flag) => flag.key));

  const storedKeys = new Set(
    stored.filter((flag) => flag.archived !== true).map((flag) => flag.key),
  );

  return {
    notStored: [...declaredKeys]
      .filter((key) => !storedKeys.has(key))
      .toSorted(),
    notDeclared: [...storedKeys]
      .filter((key) => !declaredKeys.has(key))
      .toSorted(),
  };
}

/** The Flags SDK's `ProviderData`, for `.well-known/vercel/flags`. */
export interface FlagsSdkProviderData {
  definitions: Record<string, FlagsSdkDefinition>;
  hints: { key: string; text: string }[];
}

/**
 * The part of a `flag()` declaration Flags Explorer reads. A declared flag's
 * function carries these as properties.
 */
export interface FlagsSdkDeclaredFlag {
  readonly key: string;
  readonly description?: string | undefined;
  readonly origin?: string | Readonly<Record<string, unknown>> | undefined;
  readonly options?:
    | readonly {
        readonly value: unknown;
        readonly label?: string | undefined;
      }[]
    | undefined;
  readonly defaultValue?: unknown;
}

export interface GetProviderDataOptions {
  /**
   * The app's declared flags, single or in groups such as `{ pricingFlags }`:
   * their descriptions, options and defaults join the stored definitions, and a
   * declared flag the table lacks becomes a hint.
   */
  readonly flags?: Readonly<
    Record<string, FlagsSdkDeclaredFlag | readonly FlagsSdkDeclaredFlag[]>
  >;
}

function declaredOf(
  flags: GetProviderDataOptions["flags"],
): readonly FlagsSdkDeclaredFlag[] {
  return Object.values(flags ?? {}).flatMap(
    (entry): readonly FlagsSdkDeclaredFlag[] =>
      "key" in entry ? [entry] : entry,
  );
}

function withDeclaration(
  stored: FlagsSdkDefinition | undefined,
  declared: FlagsSdkDeclaredFlag,
): FlagsSdkDefinition {
  const options =
    stored && stored.options.length > 0
      ? stored.options
      : (declared.options ?? []).map(({ value, label }) => ({
          value,
          ...(label !== undefined && { label }),
        }));

  const description = declared.description ?? stored?.description;
  const origin = declared.origin ?? stored?.origin;

  return {
    ...stored,
    options,
    ...(description !== undefined && { description }),
    ...(origin !== undefined && { origin }),
    declaredInCode: true,
    ...(declared.defaultValue !== undefined && {
      defaultValue: declared.defaultValue,
    }),
  };
}

/**
 * Flags Explorer data for every flag that isn't archived. Pass the adapter
 * factory or `{ provider, origin }`, and the declared flags in `flags`; combine
 * the result with other providers' data through `mergeProviderData`. A failed
 * load becomes a hint.
 */
export async function getProviderData(
  source: {
    readonly provider: FlagsProvider<string>;
    readonly origin?: FlagsSdkOrigin;
  },
  options: GetProviderDataOptions = {},
): Promise<FlagsSdkProviderData> {
  const declared = declaredOf(options.flags);
  let flags: readonly FlagDefinition[];

  try {
    flags = await source.provider.definitions();
  } catch (error) {
    return {
      definitions: Object.fromEntries(
        declared.map((flag) => [flag.key, withDeclaration(undefined, flag)]),
      ),
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

    const wrong = misfits(flag);

    if (wrong.length > 0) {
      hints.push({
        key: "better-supabase/variant-type",
        text: `Flag "${flag.key}" is a ${flag.type} flag, but the variants ${wrong.map((name) => `"${name}"`).join(", ")} hold another type, so they serve the fallback`,
      });
    }

    definitions[flag.key] = toFlagsSdkDefinition(flag, source.origin);
  }

  for (const key of flagDrift(declared, flags).notStored) {
    hints.push({
      key: "better-supabase/not-stored",
      text: `Flag "${key}" is declared in code but missing from the flags table, so it always serves its defaultValue`,
    });
  }

  for (const flag of declared) {
    definitions[flag.key] = withDeclaration(definitions[flag.key], flag);
  }

  return { definitions, hints };
}

/** The Flags SDK's `ApiData`: what `.well-known/vercel/flags` answers. */
export interface FlagsSdkApiData extends Partial<FlagsSdkProviderData> {
  overrideEncryptionMode?: "encrypted" | "plaintext";
}

export interface FlagsExplorerOptions {
  /**
   * How Flags Explorer stores overrides in the `vercel-flag-overrides` cookie.
   * Default `encrypted`; `plaintext` lets a Worker or a test read them without
   * `FLAGS_SECRET`.
   */
  readonly overrideEncryptionMode?: "encrypted" | "plaintext";
}

/** Provider data as the discovery endpoint answers it. */
export function flagsExplorerApiData(
  data: FlagsSdkProviderData,
  options: FlagsExplorerOptions = {},
): FlagsSdkApiData {
  return {
    ...data,
    overrideEncryptionMode: options.overrideEncryptionMode ?? "encrypted",
  };
}

export interface FlagsDiscoveryOptions extends FlagsExplorerOptions {
  /**
   * Checks the request's `Authorization` header, such as `verifyAccess` from
   * `flags`; the endpoint answers 401 when it resolves `false`.
   */
  readonly verify: (authorization: string | null) => Promise<boolean>;
  /** The `x-flags-sdk-version` header, such as `version` from `flags`. */
  readonly version?: string;
}

/**
 * The `.well-known/vercel/flags` endpoint on a WinterTC `Request`, for Hono,
 * SvelteKit or a Worker: `createFlagsDiscoveryEndpoint` from `flags/next` does
 * the same for Next.js.
 */
export function flagsDiscoveryHandler(
  getData: (
    request: Request,
  ) => FlagsSdkProviderData | Promise<FlagsSdkProviderData>,
  options: FlagsDiscoveryOptions,
): (request: Request) => Promise<Response> {
  return async (request) => {
    if (!(await options.verify(request.headers.get("authorization")))) {
      return Response.json(null, { status: 401 });
    }

    const data = flagsExplorerApiData(await getData(request), options);

    return Response.json(data, {
      headers: {
        "cache-control": "no-store",
        ...(options.version !== undefined && {
          "x-flags-sdk-version": options.version,
        }),
      },
    });
  };
}

export interface ExplorerOverridesOptions {
  /**
   * Decrypts an encrypted cookie, such as `decryptOverrides` from `flags`.
   * Without it the cookie is read as plaintext JSON (`overrideEncryptionMode:
   * "plaintext"`).
   */
  readonly decrypt?: (
    value: string,
  ) => Promise<Readonly<Record<string, unknown>> | undefined>;
}

/**
 * The flag values Flags Explorer overrides for this browser, from the
 * `vercel-flag-overrides` cookie; `{}` when there is none or it doesn't
 * decrypt. Only the server-side evaluation reads these: `flag_enabled()` in a
 * policy never sees a browser cookie.
 */
export async function explorerOverrides(
  cookies: FlagsSdkRequest["cookies"],
  options: ExplorerOverridesOptions = {},
): Promise<Readonly<Record<string, FlagValue>>> {
  const value = cookies.get(FLAG_OVERRIDES_COOKIE)?.value;

  if (value === undefined || value === "") {
    return {};
  }

  try {
    const parsed: unknown = options.decrypt
      ? await options.decrypt(value)
      : JSON.parse(decodeURIComponent(value));

    // SAFETY: Flags Explorer writes JSON values keyed by flag key.
    return typeof parsed === "object" &&
      parsed !== null &&
      !Array.isArray(parsed)
      ? (parsed as Record<string, FlagValue>)
      : {};
  } catch {
    return {};
  }
}

/**
 * The provider with Flags Explorer's overrides on top, for the OpenFeature path
 * (the Flags SDK's `flag()` reads the cookie itself). An overridden flag of the
 * asked type resolves with reason `OVERRIDE`; any other falls through. Build
 * one per request from `explorerOverrides`.
 */
export function withExplorerOverrides<Code extends string>(
  provider: FlagsProvider<Code>,
  overrides: Readonly<Record<string, FlagValue>>,
): FlagsProvider<Code> {
  const overridden = <T extends FlagValue>(
    key: string,
    fits: (value: FlagValue) => boolean,
  ): FlagResolution<T, Code> | undefined => {
    if (!Object.hasOwn(overrides, key)) {
      return undefined;
    }

    const value = overrides[key];

    // SAFETY: fits checked the override against the asked type.
    return value !== undefined && fits(value)
      ? { value: value as T, reason: "OVERRIDE" }
      : undefined;
  };

  return {
    ...provider,
    resolveBooleanEvaluation: async (key, defaultValue, context) =>
      overridden(key, (value) => typeof value === "boolean") ??
      provider.resolveBooleanEvaluation(key, defaultValue, context),
    resolveStringEvaluation: async (key, defaultValue, context) =>
      overridden(key, (value) => typeof value === "string") ??
      provider.resolveStringEvaluation(key, defaultValue, context),
    resolveNumberEvaluation: async (key, defaultValue, context) =>
      overridden(key, (value) => typeof value === "number") ??
      provider.resolveNumberEvaluation(key, defaultValue, context),
    resolveObjectEvaluation: async <T extends FlagValue>(
      key: string,
      defaultValue: T,
      context: FlagContext,
    ) =>
      overridden<T>(
        key,
        (value) => typeof value === "object" && value !== null,
      ) ?? provider.resolveObjectEvaluation(key, defaultValue, context),
  };
}

/**
 * The deployment's environment as a custom context, `{ environment }`, from
 * `VERCEL_ENV` (`production`, `preview`, `development`) or `NODE_ENV`. Pass it
 * in `contexts` so a rule can target previews: `{ variant: "on", contexts: {
 * environment: ["preview"] } }`.
 */
export function vercelEnvironmentContext(): Readonly<Record<string, string>> {
  const environment = getEnv("VERCEL_ENV") ?? getEnv("NODE_ENV");

  return environment ? { environment } : {};
}
