import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err } from "../../core/result.ts";
import { validate } from "../../core/standard.ts";
import {
  type BlockCall,
  blockCall,
  isRecord,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";

/** One setting: its Standard Schema and the value `get` returns when none is stored. */
export interface SettingEntry<S extends StandardSchemaV1 = StandardSchemaV1> {
  readonly schema: S;
  readonly default?: StandardSchemaV1.InferOutput<S>;
  /**
   * Platform settings only: the platform permission (`is_platform`) that
   * may change this key. Default `sql.modules.settings.options.platform.permission`,
   * then `settings.manage`.
   */
  readonly permission?: string;
  /**
   * Platform settings only: who reads this key, `public` (anyone, also
   * signed out), `authenticated` (default) or `staff` (holders of its
   * permission).
   */
  readonly read?: "public" | "authenticated" | "staff";
}

export type SettingEntries = Readonly<Record<string, SettingEntry>>;

/** The value type of each key: the schema output, or `undefined` without a default. */
export type SettingValues<E extends SettingEntries> = {
  readonly [K in keyof E]: E[K] extends SettingEntry<infer S>
    ? E[K] extends { readonly default: unknown }
      ? StandardSchemaV1.InferOutput<S>
      : StandardSchemaV1.InferOutput<S> | undefined
    : never;
};

/** What a scope's `set` accepts per key: the schema input. */
export type SettingInputs<E extends SettingEntries> = {
  readonly [K in keyof E]: E[K] extends SettingEntry<infer S>
    ? StandardSchemaV1.InferInput<S>
    : never;
};

export interface SettingsSpec<
  U extends SettingEntries = SettingEntries,
  O extends SettingEntries = SettingEntries,
  P extends SettingEntries = SettingEntries,
> {
  readonly user?: U;
  readonly organization?: O;
  /** Settings for the whole product, such as an admin console edits. */
  readonly platform?: P;
}

export interface SettingsConnectOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** The module schema (`sql.modules.settings.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

/** The caller's own settings. */
export interface UserSettings<E extends SettingEntries> {
  /** Every key, stored values merged over the defaults. */
  get(): AsyncResult<SettingValues<E>>;
  get<K extends keyof E & string>(key: K): AsyncResult<SettingValues<E>[K]>;
  /** Validates `value` with the key's schema, then stores the output. */
  set<K extends keyof E & string>(
    key: K,
    value: SettingInputs<E>[K],
  ): AsyncResult<SettingValues<E>[K]>;
  /** Removes the stored value, so `get` returns the default again. */
  reset(key: keyof E & string): AsyncResult<boolean>;
}

/** One organization's settings; reads need `settings.read`, writes `settings.update`. */
export interface OrganizationSettings<E extends SettingEntries> {
  get(organizationId: string): AsyncResult<SettingValues<E>>;
  get<K extends keyof E & string>(
    organizationId: string,
    key: K,
  ): AsyncResult<SettingValues<E>[K]>;
  set<K extends keyof E & string>(
    organizationId: string,
    key: K,
    value: SettingInputs<E>[K],
  ): AsyncResult<SettingValues<E>[K]>;
  reset(organizationId: string, key: keyof E & string): AsyncResult<boolean>;
}

/**
 * The product-wide settings: reads follow each key's `read`, writes need
 * its platform permission.
 */
export type PlatformSettings<E extends SettingEntries> = UserSettings<E>;

export interface SettingsClient<
  U extends SettingEntries,
  O extends SettingEntries,
  P extends SettingEntries = Record<never, never>,
> {
  readonly user: UserSettings<U>;
  readonly organization: OrganizationSettings<O>;
  readonly platform: PlatformSettings<P>;
}

export interface SettingsDefinition<
  U extends SettingEntries,
  O extends SettingEntries,
  P extends SettingEntries = Record<never, never>,
> {
  /**
   * Pass as `sql.modules.settings.options.schemas` for the database checks,
   * and the platform keys' permissions and read rules.
   */
  readonly schemas: {
    readonly user: U;
    readonly organization: O;
    readonly platform: P;
  };
  /** Typed `get`, `set` and `reset` over the settings module's functions. */
  connect(options: SettingsConnectOptions): SettingsClient<U, O, P>;
}

/**
 * Declares the app's settings with a Standard Schema per key. Values are
 * validated before they are written, and stored values that no longer match
 * their schema read as the default.
 */
export function defineSettings<
  const U extends SettingEntries = Record<never, never>,
  const O extends SettingEntries = Record<never, never>,
  const P extends SettingEntries = Record<never, never>,
>(spec: SettingsSpec<U, O, P>): SettingsDefinition<U, O, P> {
  // SAFETY: an omitted scope has no keys, which is what the empty default type says.
  const user = spec.user ?? ({} as U);
  // SAFETY: as above.
  const organization = spec.organization ?? ({} as O);
  // SAFETY: as above.
  const platform = spec.platform ?? ({} as P);
  return {
    schemas: { user, organization, platform },
    connect: (options) => {
      applyTemporal(options);
      const call = blockCall(
        options.transport,
        options.schema,
        options.mappers,
      );
      return {
        user: userScope(user, call),
        organization: organizationScope(organization, call),
        platform: platformScope(platform, call),
      };
    },
  };
}

/** Stored values merged over the defaults; unknown keys are dropped. */
async function merged(
  entries: SettingEntries,
  stored: unknown,
): Promise<Record<string, unknown>> {
  const values = isRecord(stored) ? stored : {};
  const out: Record<string, unknown> = {};
  for (const [key, entry] of Object.entries(entries)) {
    out[key] = await readValue(entry, values[key]);
  }
  return out;
}

async function readValue(
  entry: SettingEntry,
  stored: unknown,
): Promise<unknown> {
  if (stored === undefined) return entry.default;
  const parsed = await validate(entry.schema, stored);
  return parsed.ok ? parsed.data : entry.default;
}

function unknownSetting<T>(key: string): AsyncResult<T> {
  return AsyncResult.from<T>(() =>
    Promise.resolve(err(dbError("invalid_input", `Unknown setting "${key}"`))),
  );
}

/** Reads every key, or one key, through `fn`. */
function reader(
  entries: SettingEntries,
  call: BlockCall,
  fn: string,
  args: Readonly<Record<string, unknown>>,
  key: string | undefined,
): AsyncResult<unknown> {
  if (key !== undefined && !(key in entries)) return unknownSetting(key);
  return call(fn, args, async (stored) => {
    const values = await merged(entries, stored);
    return key === undefined ? values : values[key];
  });
}

/** Validates `value` with the key's schema, then writes the output through `fn`. */
function writer(
  entries: SettingEntries,
  call: BlockCall,
  fn: string,
  args: Readonly<Record<string, unknown>>,
  key: string,
  value: unknown,
): AsyncResult<unknown> {
  const entry = entries[key];
  if (!entry) return unknownSetting(key);
  return AsyncResult.from(() =>
    validate(entry.schema, value, `setting "${key}"`),
  ).andThen((output) =>
    call(fn, { ...args, key, value: { value: output ?? null } }, () => output),
  );
}

function remover(
  entries: SettingEntries,
  call: BlockCall,
  fn: string,
  args: Readonly<Record<string, unknown>>,
  key: string,
): AsyncResult<boolean> {
  if (!(key in entries)) return unknownSetting(key);
  return call(fn, { ...args, key }, (removed) => removed === true);
}

function userScope<E extends SettingEntries>(
  entries: E,
  call: BlockCall,
): UserSettings<E> {
  function get(): AsyncResult<SettingValues<E>>;
  function get<K extends keyof E & string>(
    key: K,
  ): AsyncResult<SettingValues<E>[K]>;
  function get(key?: string): AsyncResult<unknown> {
    return reader(entries, call, "get_user_settings", {}, key);
  }
  return {
    get,
    set: (key, value) =>
      // SAFETY: writer returns the key's schema output, SettingValues<E>[K].
      writer(entries, call, "set_user_setting", {}, key, value) as AsyncResult<
        SettingValues<E>[typeof key]
      >,
    reset: (key) => remover(entries, call, "reset_user_setting", {}, key),
  };
}

function organizationScope<E extends SettingEntries>(
  entries: E,
  call: BlockCall,
): OrganizationSettings<E> {
  function get(organizationId: string): AsyncResult<SettingValues<E>>;
  function get<K extends keyof E & string>(
    organizationId: string,
    key: K,
  ): AsyncResult<SettingValues<E>[K]>;
  function get(organizationId: string, key?: string): AsyncResult<unknown> {
    return reader(
      entries,
      call,
      "get_organization_settings",
      { tenant: organizationId },
      key,
    );
  }
  return {
    get,
    set: (organizationId, key, value) =>
      // SAFETY: writer returns the key's schema output, SettingValues<E>[K].
      writer(
        entries,
        call,
        "set_organization_setting",
        { tenant: organizationId },
        key,
        value,
      ) as AsyncResult<SettingValues<E>[typeof key]>,
    reset: (organizationId, key) =>
      remover(
        entries,
        call,
        "reset_organization_setting",
        { tenant: organizationId },
        key,
      ),
  };
}

function platformScope<E extends SettingEntries>(
  entries: E,
  call: BlockCall,
): PlatformSettings<E> {
  function get(): AsyncResult<SettingValues<E>>;
  function get<K extends keyof E & string>(
    key: K,
  ): AsyncResult<SettingValues<E>[K]>;
  function get(key?: string): AsyncResult<unknown> {
    return reader(entries, call, "get_platform_settings", {}, key);
  }
  return {
    get,
    set: (key, value) =>
      // SAFETY: writer returns the key's schema output, SettingValues<E>[K].
      writer(
        entries,
        call,
        "set_platform_setting",
        {},
        key,
        value,
      ) as AsyncResult<SettingValues<E>[typeof key]>,
    reset: (key) => remover(entries, call, "reset_platform_setting", {}, key),
  };
}
