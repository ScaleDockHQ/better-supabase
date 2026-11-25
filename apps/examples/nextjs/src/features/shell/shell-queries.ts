import "server-only";
import type { Bootstrap } from "better-supabase/next";

import { tenantOf } from "better-supabase/next";
import { expandBootstrapPermissions } from "better-supabase/server";
import { cacheLife, cacheTag } from "next/cache";

import type { Claims, Profile } from "@/lib/claims";

import { APPROVALS_TAG } from "@/features/approvals/approvals-cache";
import { bsbShell as bsb } from "@/lib/supabase/server-shell";

/**
 * The rows of `public.my_organizations`, as `public.shell_bootstrap` embeds
 * them.
 */
export interface ShellOrganizationRow {
  readonly id: string | null;
  readonly name: string | null;
  readonly slug: string | null;
  readonly role: string | null;
  readonly plan: string | null;
}

/** What `public.shell_bootstrap` returns through `bootstrap_shell`. */
export interface ShellData {
  readonly organizations: readonly ShellOrganizationRow[];
  readonly profile: unknown;
  readonly approvals_pending: number;
  /** The compact form of ADR 0524; expand it with `shellKeys`. */
  readonly permissions: unknown;
}

export type ShellBootstrap = Bootstrap<Claims, Profile, ShellData>;

/**
 * The one call the page shell makes: organizations, profile, pending approvals
 * and permissions. Call it as the first statement of a cache function, like
 * `bsb.cached()`: React's `cache()` inside `bsb.bootstrap` runs the call once
 * per request, whichever reader asks first.
 */
export function bootShell(
  tags: readonly string[] = [],
): Promise<ShellBootstrap> {
  return bsb.bootstrap<ShellData>({ rpc: "shell", tags });
}

/**
 * The caller's keys in `tenant` from the shell call, or `undefined` when the
 * payload has none for it (a damaged bitset, another `apiVersion`).
 */
export function shellKeys(
  shell: ShellBootstrap,
  tenant: string,
): readonly string[] | undefined {
  const expanded = expandBootstrapPermissions(shell.data?.permissions);

  return expanded?.tenants[tenant];
}

/**
 * What the shell readers share: the payload and whether a user and an
 * organization are active.
 */
export interface ShellEntry {
  readonly user: boolean;
  readonly tenant: string | undefined;
  readonly data: ShellData | null;
}

/**
 * The shell's one call, kept as one private entry. React's `cache()` in
 * `bsb.bootstrap` does not span separate `'use cache: private'` scopes, so
 * three readers that each called `bootShell` made three calls; they read this
 * entry instead. The entry follows the shortest reader (the approvals badge)
 * and carries its tag besides the tables the bootstrap entry tags.
 */
export async function getShell(): Promise<ShellEntry> {
  "use cache: private";
  cacheLife({ stale: 30, revalidate: 60, expire: 300 });
  cacheTag(APPROVALS_TAG);

  const shell = await bootShell([APPROVALS_TAG]);

  return {
    user: shell.session.kind === "user",
    tenant: tenantOf(shell.session),
    data: shell.data ?? null,
  };
}
