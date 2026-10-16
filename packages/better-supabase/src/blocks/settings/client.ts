import type { AsyncResult } from "../../core/result.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type {
  SettingEntries,
  SettingEntry,
  SettingInputs,
  Settings,
  SettingValues,
} from "./settings.ts";

import { type DbError, dbError } from "../../core/errors.ts";
import { isList, isRecord } from "../../core/guards.ts";
import { err, type Result } from "../../core/result.ts";
import { defineController, whileSignedIn } from "../controller.ts";

/** How a settings page renders a key. */
export type SettingKind = "boolean" | "number" | "text" | "choice" | "json";

/** One generated form field: a key of the settings definition and what its schema says about it. */
export interface SettingField<K extends string = string> {
  readonly key: K;
  /**
   * From the schema's Standard JSON Schema (`type` and `enum`), or from the
   * default's type for a schema library without it.
   */
  readonly kind: SettingKind;
  /** The values a `choice` allows, from the JSON Schema `enum`. */
  readonly choices: readonly (string | number)[];
  /** The JSON Schema `title` and `description`, such as zod's `.meta()`. */
  readonly title: string | undefined;
  readonly description: string | undefined;
  readonly default: unknown;
}

/** The `jsonSchema` member of a schema that implements Standard JSON Schema. */
interface JsonSchemaConverter {
  readonly input: (options: { readonly target: string }) => unknown;
}

const isConverter = (value: unknown): value is JsonSchemaConverter =>
  isRecord(value) && typeof value["input"] === "function";

const jsonSchemaOf = (
  entry: SettingEntry,
): Readonly<Record<string, unknown>> | undefined => {
  const standard: unknown = entry.schema["~standard"];
  const converter = isRecord(standard) ? standard["jsonSchema"] : undefined;
  if (!isConverter(converter)) return undefined;
  try {
    const converted = converter.input({ target: "draft-2020-12" });
    return isRecord(converted) ? converted : undefined;
  } catch {
    return undefined;
  }
};

const kindOfValue = (value: unknown): SettingKind =>
  typeof value === "boolean"
    ? "boolean"
    : typeof value === "number"
      ? "number"
      : typeof value === "string"
        ? "text"
        : "json";

const text = (value: unknown): string | undefined =>
  typeof value === "string" ? value : undefined;

function fieldOf<K extends string>(
  key: K,
  entry: SettingEntry,
): SettingField<K> {
  const schema = jsonSchemaOf(entry);
  const values = schema?.["enum"];
  const choices = isList(values)
    ? values.filter(
        (value): value is string | number =>
          typeof value === "string" || typeof value === "number",
      )
    : [];
  const type = schema?.["type"];
  const kind: SettingKind =
    choices.length > 0
      ? "choice"
      : type === "boolean"
        ? "boolean"
        : type === "number" || type === "integer"
          ? "number"
          : type === "string"
            ? "text"
            : type === undefined
              ? kindOfValue(entry.default)
              : "json";
  return {
    key,
    kind,
    choices,
    title: text(schema?.["title"]),
    description: text(schema?.["description"]),
    default: entry.default,
  };
}

/**
 * The form fields of one scope of a settings definition, in declaration
 * order: `settingFields(settings.schemas.organization)`.
 */
export function settingFields<E extends SettingEntries>(
  entries: E,
): readonly SettingField<keyof E & string>[] {
  const fields: SettingField<keyof E & string>[] = [];
  for (const key of Object.keys(entries)) {
    const entry = entries[key];
    if (!entry) continue;
    // SAFETY: `key` comes from `Object.keys(entries)`, so it is a key of E.
    fields.push(fieldOf(key as keyof E & string, entry));
  }
  return fields;
}

export interface SettingsControllerOptions<E extends SettingEntries> {
  /** One scope of the definition: `settings.schemas.user` or `settings.schemas.organization`. */
  readonly entries: E;
  readonly auth: AuthPort;
  /** The caller's own settings: a `createSettings` client. Pass this or `organization`. */
  readonly user?: Pick<Settings<E>, "getUser" | "setUser" | "resetUser">;
  /** An organization's settings: a `createSettings` client, with `organizationId`. */
  readonly organization?: Pick<
    Settings<SettingEntries, E>,
    "getOrganization" | "setOrganization" | "resetOrganization"
  >;
  /** The organization for `organization`; the page waits without one. */
  readonly organizationId?: string | null;
}

export interface SettingsSnapshot<E extends SettingEntries> {
  /** The form fields, from the definition; there before the first load. */
  readonly fields: readonly SettingField<keyof E & string>[];
  /** Stored values over the defaults; `undefined` until the first load. */
  readonly values: SettingValues<E> | undefined;
  /** The key being saved. */
  readonly saving: (keyof E & string) | undefined;
  readonly error: DbError | undefined;
}

export interface SettingsActions<E extends SettingEntries> {
  /** Validates and stores one value, then shows it; a failure is also kept in `error`. */
  readonly set: <K extends keyof E & string>(
    key: K,
    value: SettingInputs<E>[K],
  ) => Promise<Result<SettingValues<E>[K]>>;
  /**
   * `set` for a form generated from `fields`, whose controls produce plain
   * values: the key's schema validates `value` before it is stored.
   */
  readonly setField: (
    key: keyof E & string,
    value: unknown,
  ) => Promise<Result<unknown>>;
  /** Removes the stored value, so the key reads as its default again. */
  readonly reset: (key: keyof E & string) => Promise<Result<boolean>>;
  readonly refresh: () => Promise<void>;
}

export type SettingsController<E extends SettingEntries> = Controller<
  SettingsSnapshot<E>,
  SettingsActions<E>
>;

interface Store<E extends SettingEntries> {
  readonly get: () => AsyncResult<SettingValues<E>>;
  readonly set: <K extends keyof E & string>(
    key: K,
    value: SettingInputs<E>[K],
  ) => AsyncResult<SettingValues<E>[K]>;
  readonly reset: (key: keyof E & string) => AsyncResult<boolean>;
}

function storeOf<E extends SettingEntries>(
  options: SettingsControllerOptions<E>,
): Store<E> | undefined {
  const { user, organization } = options;
  if (user) {
    return {
      get: () => user.getUser(),
      set: (key, value) => user.setUser(key, value),
      reset: (key) => user.resetUser(key),
    };
  }
  if (!organization) {
    throw new TypeError(
      "better-supabase: createSettingsController needs `user` or `organization`",
    );
  }
  const organizationId = options.organizationId ?? null;
  if (organizationId === null) return undefined;
  return {
    get: () => organization.getOrganization(organizationId),
    set: (key, value) =>
      organization.setOrganization(organizationId, key, value),
    reset: (key) => organization.resetOrganization(organizationId, key),
  };
}

/**
 * One scope of the app's settings for a settings page: the form fields
 * generated from the definition, the stored values over the defaults, and
 * `set` and `reset` per key.
 */
export function createSettingsController<E extends SettingEntries>(
  options: SettingsControllerOptions<E>,
): SettingsController<E> {
  const store = storeOf(options);
  return defineController<SettingsSnapshot<E>, SettingsActions<E>>(
    {
      fields: settingFields(options.entries),
      values: undefined,
      saving: undefined,
      error: undefined,
    },
    (state) => {
      const refresh = async (): Promise<void> => {
        if (!store) return;
        const run = state.run();
        const result = await store.get();
        if (run !== state.run()) return;
        state.set(
          result.ok
            ? { values: result.data, error: undefined }
            : { error: result.error },
        );
      };
      const waiting = <T>(): Result<T> =>
        err(
          dbError("invalid_input", "No organization to save the setting for"),
        );
      const set: SettingsActions<E>["set"] = async (key, value) => {
        if (!store) return waiting();
        state.set({ saving: key, error: undefined });
        const result = await store.set(key, value);
        if (!result.ok) {
          state.set({ saving: undefined, error: result.error });
          return result;
        }
        state.set((current) => ({
          saving: undefined,
          ...(current.values === undefined
            ? {}
            : { values: { ...current.values, [key]: result.data } }),
        }));
        return result;
      };
      return {
        actions: {
          refresh,
          set,
          setField: (key, value) =>
            // SAFETY: the writer validates `value` with the key's Standard
            // Schema before it stores it, and answers `validation` otherwise.
            set(key, value as SettingInputs<E>[typeof key]),
          reset: async (key) => {
            if (!store) return waiting();
            state.set({ saving: key, error: undefined });
            const result = await store.reset(key);
            state.set(
              result.ok
                ? { saving: undefined }
                : { saving: undefined, error: result.error },
            );
            if (result.ok) await refresh();
            return result;
          },
        },
        start: () =>
          store
            ? whileSignedIn(options.auth, () => {
                void refresh();
                return;
              })
            : undefined,
      };
    },
  );
}
