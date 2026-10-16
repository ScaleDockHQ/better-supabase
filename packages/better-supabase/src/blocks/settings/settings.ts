import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BlockOptions } from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err } from "../../core/result.ts";
import { validate } from "../../core/standard.ts";
import {
  type BlockCall,
  blockCall,
  isRecord,
  applyTemporal,
} from "../shared.ts";

/** One setting: its Standard Schema and the value `get` returns when none is stored. */
export interface SettingEntry<S extends StandardSchemaV1 = StandardSchemaV1> {
  readonly schema: S;
  readonly default?: StandardSchemaV1.InferOutput<S>;
  /**
   * Platform settings only: the platform permission (`is_platform`) that
   * may change this key. Default `blocks.settings.options.platform.permission`,
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

export interface SettingsOptions<
  U extends SettingEntries = SettingEntries,
  O extends SettingEntries = SettingEntries,
  P extends SettingEntries = SettingEntries,
> extends BlockOptions {
  /** The app's settings, from `defineSettings`. */
  readonly settings: SettingsDefinition<U, O, P>;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Settings<U, O, P>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/**
 * Typed reads and writes of the caller's settings, an organization's
 * settings (reads need `settings.read`, writes `settings.update`) and the
 * product-wide settings (reads follow each key's `read`, writes need its
 * platform permission).
 */
export interface Settings<
  U extends SettingEntries = SettingEntries,
  O extends SettingEntries = SettingEntries,
  P extends SettingEntries = Record<never, never>,
> {
  /** Every key of the caller's settings, stored values merged over the defaults. */
  getUser(): AsyncResult<SettingValues<U>>;
  getUser<K extends keyof U & string>(key: K): AsyncResult<SettingValues<U>[K]>;
  /** Validates `value` with the key's schema, then stores the output. */
  setUser<K extends keyof U & string>(
    key: K,
    value: SettingInputs<U>[K],
  ): AsyncResult<SettingValues<U>[K]>;
  /** Removes the stored value, so `getUser` returns the default again. */
  resetUser(key: keyof U & string): AsyncResult<boolean>;
  getOrganization(organizationId: string): AsyncResult<SettingValues<O>>;
  getOrganization<K extends keyof O & string>(
    organizationId: string,
    key: K,
  ): AsyncResult<SettingValues<O>[K]>;
  setOrganization<K extends keyof O & string>(
    organizationId: string,
    key: K,
    value: SettingInputs<O>[K],
  ): AsyncResult<SettingValues<O>[K]>;
  resetOrganization(
    organizationId: string,
    key: keyof O & string,
  ): AsyncResult<boolean>;
  getPlatform(): AsyncResult<SettingValues<P>>;
  getPlatform<K extends keyof P & string>(
    key: K,
  ): AsyncResult<SettingValues<P>[K]>;
  setPlatform<K extends keyof P & string>(
    key: K,
    value: SettingInputs<P>[K],
  ): AsyncResult<SettingValues<P>[K]>;
  resetPlatform(key: keyof P & string): AsyncResult<boolean>;
}

export interface SettingsDefinition<
  U extends SettingEntries,
  O extends SettingEntries,
  P extends SettingEntries = Record<never, never>,
> {
  /**
   * Pass as `blocks.settings.options.schemas` for the database checks,
   * and the platform keys' permissions and read rules.
   */
  readonly schemas: {
    readonly user: U;
    readonly organization: O;
    readonly platform: P;
  };
}

/**
 * Declares the app's settings with a Standard Schema per key. Values are
 * validated before they are written, and stored values that no longer match
 * their schema read as the default. Pass the result to `createSettings`.
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
  return { schemas: { user, organization, platform } };
}

/** The settings block: typed `get`, `set` and `reset` over the settings module's functions. */
export function createSettings<
  U extends SettingEntries,
  O extends SettingEntries,
  P extends SettingEntries = Record<never, never>,
>(options: SettingsOptions<U, O, P>): Settings<U, O, P> {
  // A block built without `.using(...)` gets no definition.
  if (typeof options.settings !== "object") {
    throw new TypeError(
      "createSettings needs `settings`, the result of defineSettings()",
    );
  }
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const { user, organization, platform } = options.settings.schemas;
  function getUser(): AsyncResult<SettingValues<U>>;
  function getUser<K extends keyof U & string>(
    key: K,
  ): AsyncResult<SettingValues<U>[K]>;
  function getUser(key?: string): AsyncResult<unknown> {
    return reader(user, call, "get_user_settings", {}, key);
  }
  function getOrganization(
    organizationId: string,
  ): AsyncResult<SettingValues<O>>;
  function getOrganization<K extends keyof O & string>(
    organizationId: string,
    key: K,
  ): AsyncResult<SettingValues<O>[K]>;
  function getOrganization(
    organizationId: string,
    key?: string,
  ): AsyncResult<unknown> {
    return reader(
      organization,
      call,
      "get_organization_settings",
      { tenant: organizationId },
      key,
    );
  }
  function getPlatform(): AsyncResult<SettingValues<P>>;
  function getPlatform<K extends keyof P & string>(
    key: K,
  ): AsyncResult<SettingValues<P>[K]>;
  function getPlatform(key?: string): AsyncResult<unknown> {
    return reader(platform, call, "get_platform_settings", {}, key);
  }
  const client: Settings<U, O, P> = {
    getUser,
    setUser: (key, value) =>
      // SAFETY: writer returns the key's schema output, SettingValues<U>[K].
      writer(user, call, "set_user_setting", {}, key, value) as AsyncResult<
        SettingValues<U>[typeof key]
      >,
    resetUser: (key) => remover(user, call, "reset_user_setting", {}, key),
    getOrganization,
    setOrganization: (organizationId, key, value) =>
      // SAFETY: writer returns the key's schema output, SettingValues<O>[K].
      writer(
        organization,
        call,
        "set_organization_setting",
        { tenant: organizationId },
        key,
        value,
      ) as AsyncResult<SettingValues<O>[typeof key]>,
    resetOrganization: (organizationId, key) =>
      remover(
        organization,
        call,
        "reset_organization_setting",
        { tenant: organizationId },
        key,
      ),
    getPlatform,
    setPlatform: (key, value) =>
      // SAFETY: writer returns the key's schema output, SettingValues<P>[K].
      writer(
        platform,
        call,
        "set_platform_setting",
        {},
        key,
        value,
      ) as AsyncResult<SettingValues<P>[typeof key]>,
    resetPlatform: (key) =>
      remover(platform, call, "reset_platform_setting", {}, key),
  };
  return withBlockHooks(client, options.hooks, {
    block: "settings",
    ...(options.logger ? { logger: options.logger } : {}),
  });
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
