import "server-only";
import type { AuthSession } from "better-supabase/next";

import { postgres, userClaims } from "@/features/developer/postgres";

/**
 * One row of an admin table, read as the database owner. Check the caller's
 * permission and put the tenant in `text` before calling; a failed read throws,
 * so a cache never keeps it.
 */
export async function readAdminRows<Raw extends object>(
  session: AuthSession,
  text: string,
  params: readonly unknown[],
): Promise<readonly Raw[]> {
  const connection = postgres();

  if (!connection || !userClaims(session)) {
    throw new Error("This page needs a database URL and a signed-in user");
  }

  return connection.admin.queryRaw<Raw>(text, [...params]);
}

/**
 * Rows read as the caller, so RLS decides what the query returns. A failed read
 * throws, so a cache never keeps it.
 */
export async function readUserRows<Raw extends object>(
  session: AuthSession,
  text: string,
  params: readonly unknown[],
): Promise<readonly Raw[]> {
  const connection = postgres();
  const claims = userClaims(session);

  if (!connection || !claims) {
    throw new Error("This page needs a database URL and a signed-in user");
  }

  return connection.asUser(claims).queryRaw<Raw>(text, [...params]);
}
