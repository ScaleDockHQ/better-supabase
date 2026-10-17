"use client";

import type {
  InvitationChange,
  InvitationsActions,
  InvitationsSnapshot,
  MemberChange,
  MembersActions,
  MembersSnapshot,
  OrganizationRowSource,
  OrganizationsActions,
  OrganizationSource,
  OrganizationsSnapshot,
} from "../client.ts";
import type {
  OrganizationInvitationRow,
  OrganizationMember,
  OrganizationMembership,
  SwitchResult,
} from "../organizations.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController, useLatest } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import {
  createInvitationsController,
  createMembersController,
  createOrganizationsController,
} from "../client.ts";
import { createOrganizations } from "../organizations.ts";

export type {
  InvitationChange,
  InvitationDraft,
  MemberChange,
  OrganizationRowSource,
  OrganizationSource,
} from "../client.ts";

export interface UseOrganizationsOptions<T> {
  /**
   * The caller's organizations, such as a server action that adds the plan.
   * Default `organizations.mine()` through the browser client.
   */
  readonly load?: OrganizationSource<T>;
  /** Organizations a server already loaded: the first load is skipped. */
  readonly initial?: readonly T[];
  /** The active organization a server read from the session, used while the session has no tenant claim. */
  readonly activeId?: string | null;
  /** The tenant claim, `config.claims.tenant` (default `tenant_id`). */
  readonly claim?: string;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks.<module>.api`. */
  readonly schema?: string;
  /**
   * Runs after a switch. Default: refresh the session when the result asks
   * for it, so the token carries the new tenant claim.
   */
  readonly onSwitched?: (result: SwitchResult) => void | Promise<void>;
}

export interface OrganizationsState<T>
  extends OrganizationsSnapshot<T>, OrganizationsActions {
  /** The active organization's entry in `organizations`. */
  readonly active: T | undefined;
}

/**
 * The caller's organizations and the active one, for an organization
 * switcher: `switchTo` switches, refreshes the session and loads the list
 * again. The same hook runs in React DOM and React Native.
 *
 * ```tsx
 * const { organizations, active, switchTo } = useOrganizations();
 * ```
 */
export function useOrganizations(
  options?: UseOrganizationsOptions<OrganizationMembership>,
): OrganizationsState<OrganizationMembership>;
/** With `load`, the rows are whatever it returns. */
export function useOrganizations<T extends { readonly id: string }>(
  options: UseOrganizationsOptions<T> & {
    readonly load: OrganizationSource<T>;
  },
): OrganizationsState<T>;
export function useOrganizations(
  options: UseOrganizationsOptions<{ readonly id: string }> = {},
): OrganizationsState<{ readonly id: string }> {
  const { supabase, auth } = useBlockEnv();
  const latest = useLatest(options);
  const { schema, claim } = options;

  const view = useController(() => {
    const client = createOrganizations({
      transport: rpcTransport(supabase),
      ...(schema === undefined ? {} : { schema }),
    });

    const { initial, activeId } = latest.current;

    return createOrganizationsController<{ readonly id: string }>({
      client,
      auth,
      load: async () => {
        const { load } = latest.current;

        return load ? load() : client.mine().orThrow();
      },
      ...(initial === undefined ? {} : { initial }),
      ...(activeId === undefined ? {} : { activeId }),
      ...(claim === undefined ? {} : { claim }),
      onSwitched: async (result) => {
        const { onSwitched } = latest.current;

        if (onSwitched) {
          await onSwitched(result);
        } else if (result.refresh) {
          const { error } = await supabase.auth.refreshSession();

          if (error) {
            throw error;
          }
        }
      },
    });
  }, [supabase, auth, schema, claim, latest]).view;

  const active = view.organizations?.find(
    (organization) => organization.id === view.activeId,
  );

  return { ...view, active };
}

export interface UseMembersOptions<T> {
  /** The organization; the table waits without one. */
  readonly organizationId: string | null | undefined;
  /**
   * The members, such as a server action that adds names and avatars.
   * Default `organizations.members(id)` through the browser client.
   */
  readonly load?: OrganizationRowSource<T>;
  /** Members a server already loaded: the first load is skipped. */
  readonly initial?: readonly T[];
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks.<module>.api`. */
  readonly schema?: string;
  /** Runs after a role change or a removal committed. */
  readonly onChanged?: (change: MemberChange) => void | Promise<void>;
}

type MemberRow = { readonly userId: string; readonly role: string };

export interface MembersState<T extends { readonly role: string }>
  extends MembersSnapshot<T>, MembersActions<T["role"]> {}

/**
 * One organization's members through the browser client, for a members
 * table: `setRole` shows the new role at once, `remove` removes a member.
 * The same hook runs in React DOM and React Native.
 *
 * ```tsx
 * const { members, pending, setRole, remove } = useMembers({ organizationId });
 * ```
 */
export function useMembers(
  options: UseMembersOptions<OrganizationMember>,
): MembersState<OrganizationMember>;
/** With `load`, the rows are whatever it returns. */
export function useMembers<
  T extends { readonly userId: string; readonly role: string },
>(
  options: UseMembersOptions<T> & { readonly load: OrganizationRowSource<T> },
): MembersState<T>;
export function useMembers(
  options: UseMembersOptions<MemberRow>,
): MembersState<MemberRow> {
  const { supabase, auth } = useBlockEnv();
  const latest = useLatest(options);
  const { organizationId, schema } = options;

  return useController(() => {
    const client = createOrganizations({
      transport: rpcTransport(supabase),
      ...(schema === undefined ? {} : { schema }),
    });

    const { initial } = latest.current;

    return createMembersController<MemberRow>({
      client,
      auth,
      organizationId: organizationId ?? null,
      load: async (id) => {
        const { load } = latest.current;

        return load ? load(id) : client.members(id).orThrow();
      },
      ...(initial === undefined ? {} : { initial }),
      onChanged: async (change) => {
        await latest.current.onChanged?.(change);
      },
    });
  }, [supabase, auth, organizationId, schema, latest]).view;
}

export interface UseInvitationsOptions<T> {
  /** The organization; nothing loads or sends without one. */
  readonly organizationId: string | null | undefined;
  /** The open invitations. Default `organizations.invitations(id)` through the browser client. */
  readonly load?: OrganizationRowSource<T>;
  /** Invitations a server already loaded: the first load is skipped. */
  readonly initial?: readonly T[];
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks.<module>.api`. */
  readonly schema?: string;
  /** Runs after an invitation was sent or revoked. */
  readonly onChanged?: (change: InvitationChange) => void | Promise<void>;
}

export interface InvitationsState<T>
  extends InvitationsSnapshot<T>, InvitationsActions {}

/**
 * One organization's open invitations through the browser client, for an
 * invite dialog: `invite` sends one and keeps the token for the accept link
 * in `sent`. The same hook runs in React DOM and React Native.
 *
 * ```tsx
 * const { invite, inviting, sent, error } = useInvitations({ organizationId });
 * ```
 */
export function useInvitations(
  options: UseInvitationsOptions<OrganizationInvitationRow>,
): InvitationsState<OrganizationInvitationRow>;
/** With `load`, the rows are whatever it returns. */
export function useInvitations<T extends { readonly id: string }>(
  options: UseInvitationsOptions<T> & {
    readonly load: OrganizationRowSource<T>;
  },
): InvitationsState<T>;
export function useInvitations(
  options: UseInvitationsOptions<{ readonly id: string }>,
): InvitationsState<{ readonly id: string }> {
  const { supabase, auth } = useBlockEnv();
  const latest = useLatest(options);
  const { organizationId, schema } = options;

  return useController(() => {
    const client = createOrganizations({
      transport: rpcTransport(supabase),
      ...(schema === undefined ? {} : { schema }),
    });

    const { initial } = latest.current;

    return createInvitationsController<{ readonly id: string }>({
      client,
      auth,
      organizationId: organizationId ?? null,
      load: async (id) => {
        const { load } = latest.current;

        return load ? load(id) : client.invitations(id).orThrow();
      },
      ...(initial === undefined ? {} : { initial }),
      onChanged: async (change) => {
        await latest.current.onChanged?.(change);
      },
    });
  }, [supabase, auth, organizationId, schema, latest]).view;
}
