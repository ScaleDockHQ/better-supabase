import type { DbError } from "../../core/errors.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type {
  InvitationSent,
  InviteRequest,
  OrganizationInvitationRow,
  OrganizationMember,
  OrganizationMembership,
  Organizations,
  SwitchResult,
} from "./organizations.ts";

import { tenantOf } from "../../auth/tenant.ts";
import { dbError } from "../../core/errors.ts";
import { err, type Result, toDbError } from "../../core/result.ts";
import { defineController, whileSignedIn } from "../controller.ts";

/** Loads the caller's organizations, e.g. a server action; it throws on failure. */
export type OrganizationSource<T> = () => Promise<readonly T[]>;

export interface OrganizationsControllerOptions<
  T extends { readonly id: string } = OrganizationMembership,
> {
  readonly client: Pick<Organizations, "switch">;
  readonly auth: AuthPort;
  /** The caller's organizations, most recently used first, such as `organizations.mine()`. */
  readonly load: OrganizationSource<T>;
  /** Organizations a server already loaded: the first load is skipped. */
  readonly initial?: readonly T[];
  /** The active organization a server read from the session, used while the session has no tenant claim. */
  readonly activeId?: string | null;
  /** The tenant claim, `config.claims.tenant` (default `tenant_id`). */
  readonly claim?: string;
  /**
   * Runs after a switch: the active organization is a claim, so with
   * `result.refresh` the session has to be refreshed to carry it.
   */
  readonly onSwitched: (result: SwitchResult) => void | Promise<void>;
}

export interface OrganizationsSnapshot<T> {
  /** `undefined` until the first load. */
  readonly organizations: readonly T[] | undefined;
  /** The active organization from the session's tenant claim. */
  readonly activeId: string | undefined;
  /** The organization a switch is moving to. */
  readonly switching: string | undefined;
  readonly error: DbError | undefined;
}

export interface OrganizationsActions {
  /** Makes `organizationId` active, then runs `onSwitched`; a failure is also kept in `error`. */
  readonly switchTo: (organizationId: string) => Promise<Result<SwitchResult>>;
  readonly refresh: () => Promise<void>;
}

export type OrganizationsController<T> = Controller<
  OrganizationsSnapshot<T>,
  OrganizationsActions
>;

/**
 * The caller's organizations and the active one, for an organization
 * switcher: `switchTo` switches, refreshes the session through `onSwitched`
 * and loads the list again.
 */
export function createOrganizationsController<
  T extends { readonly id: string } = OrganizationMembership,
>(options: OrganizationsControllerOptions<T>): OrganizationsController<T> {
  // Without a tenant claim (the `profileColumn` and `resolver` sources) the
  // active organization is the server's, then the last one switched to.
  let chosen = options.activeId ?? undefined;

  const activeOf = (): string | undefined => {
    const session = options.auth.current();

    return (
      (session.status === "signed-in"
        ? tenantOf(session, options.claim)
        : undefined) ?? chosen
    );
  };

  return defineController<OrganizationsSnapshot<T>, OrganizationsActions>(
    {
      organizations: options.initial,
      activeId: activeOf(),
      switching: undefined,
      error: undefined,
    },
    (state) => {
      let ticket = 0;
      let seeded = options.initial !== undefined;

      const refresh = async (): Promise<void> => {
        const request = ++ticket;

        try {
          const organizations = await options.load();

          if (request === ticket) {
            state.set({ organizations, error: undefined });
          }
        } catch (cause) {
          if (request === ticket) {
            state.set({ error: toDbError(cause) });
          }
        }
      };

      return {
        actions: {
          refresh,
          switchTo: async (organizationId) => {
            state.set({ switching: organizationId, error: undefined });
            const result = await options.client.switch(organizationId);

            if (!result.ok) {
              state.set({ switching: undefined, error: result.error });

              return result;
            }

            try {
              await options.onSwitched(result.data);
            } catch (cause) {
              const error = toDbError(cause);
              state.set({ switching: undefined, error });

              return err(error);
            }

            chosen = result.data.organizationId;
            state.set({ switching: undefined, activeId: activeOf() });
            await refresh();

            return result;
          },
        },
        start: () => {
          const unsubscribe = options.auth.subscribe(() => {
            state.set({ activeId: activeOf() });
          });

          state.set({ activeId: activeOf() });

          const stop = whileSignedIn(options.auth, () => {
            if (seeded) {
              seeded = false;
            } else {
              void refresh();
            }

            return;
          });

          return () => {
            unsubscribe();
            stop();
          };
        },
      };
    },
  );
}

/** Loads one organization's rows, e.g. a server action; it throws on failure. */
export type OrganizationRowSource<T> = (
  organizationId: string,
) => Promise<readonly T[]>;

/** A member change that committed, for `onChanged`. */
export type MemberChange =
  | {
      readonly kind: "role";
      readonly organizationId: string;
      readonly userId: string;
      readonly role: string;
    }
  | {
      readonly kind: "removed";
      readonly organizationId: string;
      readonly userId: string;
    };

export interface MembersControllerOptions<
  T extends { readonly userId: string; readonly role: string } =
    OrganizationMember,
> {
  readonly client: Pick<Organizations, "updateMemberRole" | "removeMember">;
  readonly auth: AuthPort;
  /** The organization; the table waits without one. */
  readonly organizationId: string | null;
  /** The organization's members, such as `organizations.members(id)` or a server action that adds profiles. */
  readonly load: OrganizationRowSource<T>;
  /** Members a server already loaded: the first load is skipped. */
  readonly initial?: readonly T[];
  /**
   * Runs after a role change or a removal committed, such as a server
   * action that refreshes the member's session. A throw is kept in `error`.
   */
  readonly onChanged?: (change: MemberChange) => void | Promise<void>;
}

export interface MembersSnapshot<T> {
  /** `undefined` until the first load. */
  readonly members: readonly T[] | undefined;
  /** The user ids with a role change or a removal in flight. */
  readonly pending: readonly string[];
  readonly error: DbError | undefined;
}

export interface MembersActions<Role extends string = string> {
  /** Changes a member's role, shown at once and put back when it fails. */
  readonly setRole: (userId: string, role: Role) => Promise<Result<true>>;
  /** Removes a member from the organization, then loads the table again. */
  readonly remove: (userId: string) => Promise<Result<true>>;
  readonly refresh: () => Promise<void>;
}

export type MembersController<
  T extends { readonly userId: string; readonly role: string },
> = Controller<MembersSnapshot<T>, MembersActions<T["role"]>>;

const without = (list: readonly string[], id: string): readonly string[] =>
  list.filter((each) => each !== id);

const noOrganization = (): Result<never> =>
  err(dbError("invalid_input", "No organization is active"));

/**
 * One organization's members for a members table: `setRole` changes a
 * role optimistically, `remove` removes a member, and both run
 * `onChanged` once the database committed.
 */
export function createMembersController<
  T extends { readonly userId: string; readonly role: string } =
    OrganizationMember,
>(options: MembersControllerOptions<T>): MembersController<T> {
  const { client, organizationId } = options;

  return defineController<MembersSnapshot<T>, MembersActions<T["role"]>>(
    { members: options.initial, pending: [], error: undefined },
    (state) => {
      let ticket = 0;
      let seeded = options.initial !== undefined;

      const refresh = async (): Promise<void> => {
        if (organizationId === null) {
          return;
        }

        const request = ++ticket;

        try {
          const members = await options.load(organizationId);

          if (request === ticket) {
            state.set({ members, error: undefined });
          }
        } catch (cause) {
          if (request === ticket) {
            state.set({ error: toDbError(cause) });
          }
        }
      };

      const changed = async (change: MemberChange): Promise<void> => {
        try {
          await options.onChanged?.(change);
        } catch (cause) {
          state.set({ error: toDbError(cause) });
        }
      };

      const withRole =
        (userId: string, role: T["role"]) =>
        (current: MembersSnapshot<T>): Partial<MembersSnapshot<T>> => ({
          members: current.members?.map((member) =>
            member.userId === userId ? { ...member, role } : member,
          ),
        });

      return {
        actions: {
          refresh,
          setRole: async (userId, role) => {
            if (organizationId === null) {
              return noOrganization();
            }

            const before = state
              .get()
              .members?.find((member) => member.userId === userId);

            // A load that started before the change would answer without it.
            ticket += 1;
            state.set((current) => ({
              ...withRole(userId, role)(current),
              pending: [...current.pending, userId],
              error: undefined,
            }));

            const result = await client.updateMemberRole(
              organizationId,
              userId,
              role,
            );

            state.set((current) => ({
              ...(result.ok || before === undefined
                ? {}
                : withRole(userId, before.role)(current)),
              pending: without(current.pending, userId),
              ...(result.ok ? {} : { error: result.error }),
            }));

            if (result.ok) {
              await changed({ kind: "role", organizationId, userId, role });
            }

            return result;
          },
          remove: async (userId) => {
            if (organizationId === null) {
              return noOrganization();
            }

            state.set((current) => ({
              pending: [...current.pending, userId],
              error: undefined,
            }));
            const result = await client.removeMember(organizationId, userId);
            ticket += 1;
            state.set((current) => ({
              pending: without(current.pending, userId),
              ...(result.ok
                ? {
                    members: current.members?.filter(
                      (member) => member.userId !== userId,
                    ),
                  }
                : { error: result.error }),
            }));

            if (result.ok) {
              await refresh();
              await changed({ kind: "removed", organizationId, userId });
            }

            return result;
          },
        },
        start: () =>
          organizationId === null
            ? undefined
            : whileSignedIn(options.auth, () => {
                if (seeded) {
                  seeded = false;
                } else {
                  void refresh();
                }

                return;
              }),
      };
    },
  );
}

/** What `invite` takes: the organization comes from the controller. */
export type InvitationDraft = Omit<InviteRequest, "organizationId">;

/** An invitation change that committed, for `onChanged`. */
export type InvitationChange =
  | {
      readonly kind: "invited";
      readonly organizationId: string;
      readonly sent: InvitationSent;
    }
  | {
      readonly kind: "revoked";
      readonly organizationId: string;
      readonly invitationId: string;
    };

export interface InvitationsControllerOptions<
  T extends { readonly id: string } = OrganizationInvitationRow,
> {
  readonly client: Pick<Organizations, "invite" | "revokeInvitation">;
  readonly auth: AuthPort;
  /** The organization; nothing loads or sends without one. */
  readonly organizationId: string | null;
  /** The open invitations, such as `organizations.invitations(id)`. */
  readonly load: OrganizationRowSource<T>;
  /** Invitations a server already loaded: the first load is skipped. */
  readonly initial?: readonly T[];
  /**
   * Runs after an invitation was sent or revoked, such as a server action
   * that completes an onboarding step. A throw is kept in `error`.
   */
  readonly onChanged?: (change: InvitationChange) => void | Promise<void>;
}

export interface InvitationsSnapshot<T> {
  /** The open invitations; `undefined` until the first load. */
  readonly invitations: readonly T[] | undefined;
  /** Whether an invitation is being sent. */
  readonly inviting: boolean;
  /** The last invitation sent, with the token for the accept link, until `clear`. */
  readonly sent: InvitationSent | undefined;
  /** The invitation ids with a revoke in flight. */
  readonly revoking: readonly string[];
  readonly error: DbError | undefined;
}

export interface InvitationsActions {
  /** Invites `email` with `role`, then loads the list again; a failure is also kept in `error`. */
  readonly invite: (draft: InvitationDraft) => Promise<Result<InvitationSent>>;
  /** Revokes an open invitation; `false` when it was not open. */
  readonly revoke: (invitationId: string) => Promise<Result<boolean>>;
  /** Forgets `sent` and `error`, such as when the dialog closes. */
  readonly clear: () => void;
  readonly refresh: () => Promise<void>;
}

export type InvitationsController<T> = Controller<
  InvitationsSnapshot<T>,
  InvitationsActions
>;

/**
 * One organization's open invitations for an invite dialog: `invite` sends
 * one and keeps its token in `sent` for the accept link, `revoke` revokes
 * one, and both load the list again.
 */
export function createInvitationsController<
  T extends { readonly id: string } = OrganizationInvitationRow,
>(options: InvitationsControllerOptions<T>): InvitationsController<T> {
  const { client, organizationId } = options;

  return defineController<InvitationsSnapshot<T>, InvitationsActions>(
    {
      invitations: options.initial,
      inviting: false,
      sent: undefined,
      revoking: [],
      error: undefined,
    },
    (state) => {
      let ticket = 0;
      let seeded = options.initial !== undefined;

      const refresh = async (): Promise<void> => {
        if (organizationId === null) {
          return;
        }

        const request = ++ticket;

        try {
          const invitations = await options.load(organizationId);

          if (request === ticket) {
            state.set({ invitations, error: undefined });
          }
        } catch (cause) {
          if (request === ticket) {
            state.set({ error: toDbError(cause) });
          }
        }
      };

      const changed = async (change: InvitationChange): Promise<void> => {
        try {
          await options.onChanged?.(change);
        } catch (cause) {
          state.set({ error: toDbError(cause) });
        }
      };

      return {
        actions: {
          refresh,
          clear: () => {
            state.set({ sent: undefined, error: undefined });
          },
          invite: async (draft) => {
            if (organizationId === null) {
              return noOrganization();
            }

            state.set({ inviting: true, sent: undefined, error: undefined });
            const result = await client.invite({ ...draft, organizationId });
            state.set(
              result.ok
                ? { inviting: false, sent: result.data }
                : { inviting: false, error: result.error },
            );

            if (result.ok) {
              await refresh();
              await changed({
                kind: "invited",
                organizationId,
                sent: result.data,
              });
            }

            return result;
          },
          revoke: async (invitationId) => {
            if (organizationId === null) {
              return noOrganization();
            }

            state.set((current) => ({
              revoking: [...current.revoking, invitationId],
              error: undefined,
            }));
            const result = await client.revokeInvitation(invitationId);
            state.set((current) => ({
              revoking: without(current.revoking, invitationId),
              ...(result.ok ? {} : { error: result.error }),
            }));

            if (result.ok) {
              await refresh();
              await changed({ kind: "revoked", organizationId, invitationId });
            }

            return result;
          },
        },
        start: () =>
          organizationId === null
            ? undefined
            : whileSignedIn(options.auth, () => {
                if (seeded) {
                  seeded = false;
                } else {
                  void refresh();
                }

                return;
              }),
      };
    },
  );
}
