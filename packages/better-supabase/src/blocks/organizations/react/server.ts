import type {
  useInvitations as useClientInvitations,
  useMembers as useClientMembers,
  useOrganizations as useClientOrganizations,
} from "./index.ts";

export type {
  InvitationChange,
  InvitationDraft,
  InvitationsState,
  MemberChange,
  MembersState,
  OrganizationRowSource,
  OrganizationSource,
  OrganizationsState,
  UseInvitationsOptions,
  UseMembersOptions,
  UseOrganizationsOptions,
} from "./index.ts";

/**
 * The `react-server` build of `useOrganizations`: call `organizations.mine()`
 * instead.
 */
export const useOrganizations: typeof useClientOrganizations = () => {
  throw new Error(
    "better-supabase: useOrganizations() runs in Client Components only. In Server Components call `organizations.mine()` instead.",
  );
};

/**
 * The `react-server` build of `useMembers`: call `organizations.members()`
 * instead.
 */
export const useMembers: typeof useClientMembers = () => {
  throw new Error(
    "better-supabase: useMembers() runs in Client Components only. In Server Components call `organizations.members()` instead.",
  );
};

/**
 * The `react-server` build of `useInvitations`: call
 * `organizations.invitations()` instead.
 */
export const useInvitations: typeof useClientInvitations = () => {
  throw new Error(
    "better-supabase: useInvitations() runs in Client Components only. In Server Components call `organizations.invitations()` instead.",
  );
};
