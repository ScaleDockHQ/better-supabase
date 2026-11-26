import "server-only";
import type { Bootstrap } from "better-supabase/next";

import { tenantOf, toSession } from "better-supabase/next";
import { expandBootstrapPermissions } from "better-supabase/server";
import { cacheLife, cacheTag } from "next/cache";
import * as v from "valibot";

import type { Claims, Profile } from "@/lib/claims";

import { tags } from "@/lib/supabase/generated.tags";
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

const ShellDataSchema = v.object({
  organizations: v.array(
    v.object({
      id: v.nullable(v.string()),
      name: v.nullable(v.string()),
      slug: v.nullable(v.string()),
      role: v.nullable(v.string()),
      plan: v.nullable(v.string()),
    }),
  ),
  profile: v.unknown(),
  approvals_pending: v.number(),
  permissions: v.unknown(),
});

/** The functions the kept shell entry reads through `shell_bootstrap`. */
const SHELL_TABLES = ["memberships", "organizations", "subscriptions"] as const;

/**
 * The shell's one call as a kept entry per user, organization, authorization
 * version, schema hash and library version (`bsb.kept` builds the key). A write
 * to one of its tables, a `refreshCaller(auth)` that evicts the session, and
 * the approvals tag expire it, so an organization switch and a role change show
 * on the next read. It does not call `session_active()`: a banned user's entry
 * ends with the session eviction or after its 60 second life.
 */
const keptShell = bsb.kept(
  async ({ auth, db }): Promise<ShellEntry> => {
    const session = toSession(auth);
    const tenant = tenantOf(session);

    if (session.kind !== "user") {
      return { user: false, tenant, data: null };
    }

    const result = await db.$executor.rpc?.(
      "shell_bootstrap",
      { args: tenant === undefined ? {} : { tenant } },
      { schema: "public", errorMappers: [] },
    );

    const parsed = result?.ok
      ? v.safeParse(ShellDataSchema, result.data)
      : undefined;

    const data: ShellData | null = parsed?.success ? parsed.output : null;

    return { user: true, tenant, data };
  },
  {
    name: "shell",
    tables: SHELL_TABLES,
    tags: [tags.approvals()],
    life: { revalidate: 60, expire: 300 },
  },
);

/**
 * The shell's one call, read through the kept entry above and held as one
 * private entry. React's `cache()` in `bsb.bootstrap` does not span separate
 * `'use cache: private'` scopes, so three readers that each called `bootShell`
 * made three calls; they read this entry instead. A hard load, a second user of
 * the organization and a load after a restart read the kept entry and make no
 * database call when it is warm. The entry follows the shortest reader (the
 * approvals badge) and carries its tag besides the tables above.
 */
export async function getShell(): Promise<ShellEntry> {
  "use cache: private";
  cacheLife({ stale: 30, revalidate: 60, expire: 300 });
  cacheTag(tags.approvals());

  return keptShell();
}
