"use client";

import type {
  OrganizationsActions,
  OrganizationSource,
  OrganizationsSnapshot,
} from "../client.ts";
import type { OrganizationMembership, SwitchResult } from "../organizations.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController, useLatest } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createOrganizationsController } from "../client.ts";
import { createOrganizations } from "../organizations.ts";

export type { OrganizationSource } from "../client.ts";

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
        if (onSwitched) await onSwitched(result);
        else if (result.refresh) {
          const { error } = await supabase.auth.refreshSession();
          if (error) throw error;
        }
      },
    });
  }, [supabase, auth, schema, claim, latest]).view;
  const active = view.organizations?.find(
    (organization) => organization.id === view.activeId,
  );
  return { ...view, active };
}
