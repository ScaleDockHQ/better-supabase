"use client";

import type { SettingsActions, SettingsSnapshot } from "../client.ts";
import type { SettingEntries, SettingsDefinition } from "../settings.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createSettingsController } from "../client.ts";

export type { SettingField, SettingKind } from "../client.ts";

export interface UseSettingsOptions<S extends "user" | "organization"> {
  /** Which part of the definition the page edits. */
  readonly scope: S;
  /** The organization, for `scope: "organization"`; the page waits without one. */
  readonly organizationId?: string | null;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks.<module>.api`. */
  readonly schema?: string;
}

export interface SettingsState<E extends SettingEntries>
  extends SettingsSnapshot<E>, SettingsActions<E> {}

/**
 * One scope of a `defineSettings()` definition for a settings page,
 * through the browser client: `fields` to render, generated from the
 * definition, the stored `values`, and `set` and `reset` per key. The same
 * hook runs in React DOM and React Native.
 *
 * ```tsx
 * const { fields, values, set } = useSettings(settings, { scope: "organization", organizationId });
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
    const client = settings.connect({
      transport: rpcTransport(supabase),
      ...(schema === undefined ? {} : { schema }),
    });
    return scope === "user"
      ? createSettingsController({
          entries: settings.schemas.user,
          auth,
          user: client.user,
        })
      : createSettingsController({
          entries: settings.schemas.organization,
          auth,
          organization: client.organization,
          organizationId: organizationId ?? null,
        });
  }, [settings, supabase, auth, scope, organizationId, schema]).view;
}
