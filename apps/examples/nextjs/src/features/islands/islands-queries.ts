import "server-only";
import { tenantOf } from "better-supabase/next";

import { bsb } from "@/lib/supabase/server";

export const ISLAND_TABLES = [
  "customers",
  "notes",
  "contacts",
  "tags",
  "tasks",
] as const;

export type IslandTable = (typeof ISLAND_TABLES)[number];

/** The caller as plain values, so a cached reader can take them as arguments. */
export interface IslandSession {
  readonly email: string | null;
  readonly organizationId: string | null;
  /** Seconds since epoch. */
  readonly expiresAt: number | null;
  /** Seconds since epoch. */
  readonly issuedAt: number | null;
  readonly authzVersion: number | null;
}

/**
 * Every island calls this. Each `'use cache: private'` scope runs it again, but
 * the token verifies once per request: the session memo keys on its hash.
 */
export async function getIslandSession(): Promise<IslandSession | null> {
  "use cache: private";
  const { session } = await bsb.cached();

  if (session.kind !== "user") {
    return null;
  }

  return {
    email: session.user.email ?? null,
    organizationId: tenantOf(session) ?? null,
    expiresAt: session.expiresAt,
    issuedAt: session.issuedAt,
    authzVersion: session.authzVersion,
  };
}

/**
 * One table's row count in the organization. RLS scopes the count; the
 * organization id keys the cache entry, and the table tag revalidates it.
 */
export async function getTableCount(
  table: IslandTable,
  organizationId: string,
): Promise<number> {
  "use cache: private";
  const { db } = await bsb.cached({ tables: [table] });

  switch (table) {
    case "customers": {
      return db.customers.count({ where: { organizationId } }).orThrow();
    }

    case "notes": {
      return db.notes.count({ where: { organizationId } }).orThrow();
    }

    case "contacts": {
      return db.contacts.count({ where: { organizationId } }).orThrow();
    }

    case "tags": {
      return db.tags.count({ where: { organizationId } }).orThrow();
    }

    case "tasks": {
      return db.tasks.count({ where: { organizationId } }).orThrow();
    }

    default: {
      const exhaustive: never = table;

      return exhaustive;
    }
  }
}
