import type { useOrganizations as useClientOrganizations } from "./index.ts";

export type {
  OrganizationSource,
  OrganizationsState,
  UseOrganizationsOptions,
} from "./index.ts";

/** The `react-server` build of `useOrganizations`: call `organizations.mine()` instead. */
export const useOrganizations: typeof useClientOrganizations = () => {
  throw new Error(
    "better-supabase: useOrganizations() runs in Client Components only. In Server Components call `organizations.mine()` instead.",
  );
};
