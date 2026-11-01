import "server-only";
import type {
  ConsentStatus,
  LegalBasis,
} from "better-supabase/blocks/consents";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
async function settle<T>(load: () => Promise<T | null>): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** A client as the list shows it, serializable. */
export interface ClientRow {
  readonly id: string;
  readonly name: string;
  readonly status: string;
}

const CLIENT_LIMIT = 200;

async function loadClients(): Promise<readonly ClientRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  return db.customers
    .list({
      select: ["id", "name", "status"],
      orderBy: { name: "asc" },
      limit: CLIENT_LIMIT,
    })
    .orThrow();
}

/** The caller's clients by name: the customers they can read. */
export function getClients(): Promise<Loaded<readonly ClientRow[]>> {
  return settle(loadClients);
}

async function loadClient(id: string): Promise<ClientRow | "missing" | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const [client] = await db.customers
    .list({ select: ["id", "name", "status"], where: { id }, limit: 1 })
    .orThrow();

  return client ?? "missing";
}

/** One client, or `"missing"` when it doesn't exist or the caller can't read it. */
export function getClient(id: string): Promise<Loaded<ClientRow | "missing">> {
  return settle(() => loadClient(id));
}

/** A client's latest decision on one purpose, serializable. */
export interface ConsentRow {
  readonly id: string;
  readonly purpose: string;
  readonly version: string;
  readonly legalBasis: LegalBasis;
  readonly status: ConsentStatus;
  readonly grantedAt: string;
  readonly validUntil: string | null;
}

async function loadConsents(id: string): Promise<readonly ConsentRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const consents = await db.consents
    .list({ subject: { type: "customer", id } })
    .orThrow();

  return consents.map((consent) => ({
    id: consent.id,
    purpose: consent.purposeTitle,
    version: consent.purposeVersion,
    legalBasis: consent.legalBasis,
    status: consent.status,
    grantedAt: consent.grantedAt.toString(),
    validUntil: consent.validUntil?.toString() ?? null,
  }));
}

/** The client's latest consent decision per purpose. */
export function getConsents(
  id: string,
): Promise<Loaded<readonly ConsentRow[]>> {
  return settle(() => loadConsents(id));
}

/** One logged read of the client's record, serializable. */
export interface AccessRow {
  readonly id: string;
  readonly reader: string | null;
  readonly at: string;
  readonly purpose: string | null;
  readonly emergency: boolean;
  /**
   * The block and function that returned the record, such as
   * `subjects.record_summary`.
   */
  readonly source: string | null;
}

async function loadAccessLog(id: string): Promise<readonly AccessRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const reads = await db.subjects.reads
    .list({ subject: { type: "customer", id } })
    .orThrow();

  return reads.map((read) => ({
    id: read.id,
    reader: read.actorName ?? null,
    at: read.at.toString(),
    purpose: read.purpose ?? null,
    emergency: read.emergency,
    source:
      read.block === undefined
        ? null
        : [read.block, read.function].filter(Boolean).join("."),
  }));
}

/**
 * Who read the client's record, newest first. Holders of `audit.read` and the
 * leads on the client's team may ask; anyone else gets an error.
 */
export function getAccessLog(
  id: string,
): Promise<Loaded<readonly AccessRow[]>> {
  return settle(() => loadAccessLog(id));
}

/**
 * Logs that the caller opened the client's dossier. The dossier reads plain
 * tables, which log nothing on their own; a second open within a minute writes
 * no new entry.
 */
export async function logDossierRead(id: string): Promise<void> {
  const { db } = await bsb.cached();

  await db.subjects.reads.log({
    subject: { type: "customer", id },
    purpose: "care",
  });
}
