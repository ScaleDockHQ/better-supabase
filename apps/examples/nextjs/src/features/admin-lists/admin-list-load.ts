import "server-only";
import type { AuthSession } from "better-supabase/next";

import type { AdminList, AdminListQuery } from "@/lib/admin-list";

import { postgres, userClaims } from "@/features/developer/postgres";

import type { AdminListRaw, AdminListSource } from "./admin-list-sql";

import { runAdminList } from "./admin-list-sql";

/**
 * Runs an admin list as the caller (`user`: RLS decides the rows) or as the
 * database owner (`admin`: the source's `scope` limits the tenant, so check the
 * permission before calling). A failed read throws, so a cache never keeps it.
 */
export async function loadAdminList<
  Raw extends AdminListRaw,
  Out extends { readonly id: string },
>(options: {
  readonly session: AuthSession;
  readonly tenant: string;
  readonly list: AdminList;
  readonly source: AdminListSource<Raw, Out>;
  readonly access: "user" | "admin";
  readonly query: AdminListQuery;
}) {
  const connection = postgres();

  if (!connection) {
    throw new Error("This page needs a database URL");
  }

  const claims = userClaims(options.session);

  if (!claims) {
    throw new Error("This page needs a signed-in user");
  }

  const sql =
    options.access === "admin" ? connection.admin : connection.asUser(claims);

  return runAdminList(
    sql,
    options.list,
    options.source,
    options.tenant,
    options.query,
  );
}

/**
 * Whether the signed-in user holds a platform permission (a role in
 * `platform_roles`, not a membership). Platform pages read as the database
 * owner, so check this first.
 */
export async function holdsPlatformPermission(
  session: AuthSession,
  permission: string,
): Promise<boolean> {
  const connection = postgres();
  const claims = userClaims(session);

  if (!connection || !claims) {
    return false;
  }

  const rows = await connection
    .asUser(claims)
    .queryRaw<{ allowed: boolean | null }>(
      "select better_supabase.is_platform($1) as allowed",
      [permission],
    );

  return rows[0]?.allowed === true;
}
