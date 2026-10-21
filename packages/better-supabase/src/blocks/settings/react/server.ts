import type { useSettings as useClientSettings } from "./index.ts";

export type {
  SettingField,
  SettingKind,
  SettingsState,
  UseSettingsOptions,
} from "./index.ts";

/**
 * The `react-server` build of `useSettings`: call
 * `createSettings(...).getUser()` instead.
 */
export const useSettings: typeof useClientSettings = () => {
  throw new Error(
    "better-supabase: useSettings() runs in Client Components only. In Server Components call `createSettings(...).getUser()` or `.getOrganization(organizationId)` instead.",
  );
};
