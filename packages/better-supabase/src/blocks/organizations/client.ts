import type { DbError } from "../../core/errors.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type {
  OrganizationMembership,
  Organizations,
  SwitchResult,
} from "./organizations.ts";

import { tenantOf } from "../../auth/tenant.ts";
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
          if (request === ticket)
            state.set({ organizations, error: undefined });
        } catch (cause) {
          if (request === ticket) state.set({ error: toDbError(cause) });
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
            if (seeded) seeded = false;
            else void refresh();
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
