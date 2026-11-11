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
