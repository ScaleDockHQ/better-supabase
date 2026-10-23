"use client";

import type {
  SettingEntries,
  SettingsActions,
  SettingsDefinition,
  SettingsSnapshot,
} from "better-supabase/blocks/settings";

import { rpcTransport } from "better-supabase/blocks";
import {
  createSettings,
  createSettingsController,
} from "better-supabase/blocks/settings";
import { useBlockEnv, useController } from "better-supabase/react";

export type {
  SettingField,
  SettingKind,
} from "better-supabase/blocks/settings";

export interface UseSettingsOptions<S extends "user" | "organization"> {
  /** Which part of the definition the page edits. */
  readonly scope: S;
  /** The organization, for `scope: "organization"`; the page waits without one. */
  readonly organizationId?: string | null;
  /**
   * The schema the calls go to: the module schema (default `better_supabase`),
   * or the API schema from `blocks.<module>.api`.
   */
  readonly schema?: string;
}

export interface SettingsState<E extends SettingEntries>
  extends SettingsSnapshot<E>, SettingsActions<E> {}

/**
 * One scope of a `defineSettings()` definition for a settings page, through the
 * browser client: `fields` to render, generated from the definition, the stored
 * `values`, and `set` and `reset` per key. The same hook runs in React DOM and
 * React Native.
 *
 * ```tsx
 * const { fields, values, set } = useSettings(settings, {
 *   scope: "organization",
 *   organizationId,
 * });
 * ```
 */
export function useSettings<
  U extends SettingEntries,
  O extends SettingEntries,
  P extends SettingEntries,
>(
  settings: SettingsDefinition<U, O, P>,
  options: UseSettingsOptions<"user">,
): SettingsState<U>;
export function useSettings<
  U extends SettingEntries,
  O extends SettingEntries,
  P extends SettingEntries,
>(
  settings: SettingsDefinition<U, O, P>,
  options: UseSettingsOptions<"organization">,
): SettingsState<O>;
export function useSettings(
  settings: SettingsDefinition<SettingEntries, SettingEntries, SettingEntries>,
  options: UseSettingsOptions<"user" | "organization">,
): SettingsState<SettingEntries> {
  const { supabase, auth } = useBlockEnv();
  const { scope, organizationId, schema } = options;

  return useController(() => {
    const client = createSettings({
      settings,
      transport: rpcTransport(supabase),
      ...(schema === undefined ? {} : { schema }),
    });

    return scope === "user"
      ? createSettingsController({
          entries: settings.schemas.user,
          auth,
          user: client,
        })
      : createSettingsController({
          entries: settings.schemas.organization,
          auth,
          organization: client,
          organizationId: organizationId ?? null,
        });
  }, [settings, supabase, auth, scope, organizationId, schema]).view;
}
