import "server-only";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import { Temporal } from "temporal-polyfill";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

import { customerAttachments } from "./customer-attachments";

/** What the cards on the customer page render: the rows, or a failed read. */
export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" };

const SUBJECT = "customer";

/**
 * A failed read throws inside the cached loader, so it is never cached and
 * Retry (`refresh()`) reads again; here it becomes the card's error state.
 */
async function settle<T>(load: () => Promise<T>): Promise<Loaded<T>> {
  try {
    return { kind: "ok", data: await load() };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

async function caller() {
  const { session, supabase, db } = await bs.cached();
  const organizationId = tenantOf(session);

  if (!organizationId) {
    throw new Error("No active organization");
  }

  return { organizationId, supabase, db };
}

export interface ShareLinkRow {
  readonly id: string;
  readonly role: string;
  /** Epoch milliseconds; `null` for a link without an expiry. */
  readonly expiresAt: number | null;
  readonly revokedAt: number | null;
  /** Past its expiry when the list was read. */
  readonly expired: boolean;
}

async function loadShareLinks(
  customerId: string,
): Promise<readonly ShareLinkRow[]> {
  "use cache: private";
  const { organizationId, supabase } = await caller();

  const now = Temporal.Now.instant().epochMilliseconds;

  const links = await blocks(supabase, organizationId)
    .shareLinks.list({ type: SUBJECT, id: customerId })
    .orThrow();

  return links.map((link) => ({
    id: link.id,
    role: link.role,
    expiresAt: link.expiresAt?.epochMilliseconds ?? null,
    revokedAt: link.revokedAt?.epochMilliseconds ?? null,
    expired: link.expiresAt !== null && link.expiresAt.epochMilliseconds <= now,
  }));
}

/** The share links the caller created or may read, revoked ones last. */
export function getShareLinks(customerId: string) {
  return settle(() => loadShareLinks(customerId));
}

export interface AttachmentRow {
  readonly id: string;
  readonly name: string;
  readonly size: number;
  readonly status: "pending" | "clean" | "infected" | "failed";
  /** `false` until the browser finished the upload and it was confirmed. */
  readonly uploaded: boolean;
  readonly createdAt: number;
}

async function loadAttachments(
  customerId: string,
): Promise<readonly AttachmentRow[]> {
  "use cache: private";
  const { organizationId, supabase } = await caller();

  const files = await customerAttachments(supabase, organizationId)
    .list({ type: SUBJECT, id: customerId })
    .orThrow();

  return files.map((file) => ({
    id: file.id,
    name: file.name,
    size: file.size,
    status: file.status,
    uploaded: file.uploadedAt !== undefined,
    createdAt: file.createdAt.epochMilliseconds,
  }));
}

/** The customer's files, newest first. */
export function getAttachments(customerId: string) {
  return settle(() => loadAttachments(customerId));
}

export interface CustomerOption {
  readonly id: string;
  readonly name: string;
}

export interface RelatedCustomer {
  readonly id: string;
  /** The kind as read from this customer's side, such as `relates`. */
  readonly kind: string;
  readonly subjectType: string;
  readonly subjectId: string;
}

export interface Relations {
  readonly links: readonly RelatedCustomer[];
  /** The other customers the picker offers, by name. */
  readonly options: readonly CustomerOption[];
}

async function loadRelations(customerId: string): Promise<Relations> {
  "use cache: private";
  const { organizationId, supabase, db } = await caller();

  const [links, customers] = await Promise.all([
    blocks(supabase, organizationId)
      .relations.of({ type: SUBJECT, id: customerId })
      .orThrow(),
    db.customers
      .findMany({
        select: ["id", "name"],
        orderBy: { name: "asc" },
        limit: 200,
      })
      .orThrow(),
  ]);

  return {
    links: links.map((link) => ({
      id: link.id,
      kind: link.kind,
      subjectType: link.subject.type,
      subjectId: link.subject.id,
    })),
    options: customers.filter((row) => row.id !== customerId),
  };
}

/** The records linked to the customer, and the customers it can link to. */
export function getRelations(customerId: string) {
  return settle(() => loadRelations(customerId));
}

export interface VersionRow {
  readonly id: string;
  readonly number: number;
  readonly label: string | null;
  readonly source: "manual" | "auto" | "restore";
  readonly createdAt: number;
}

async function loadVersions(
  customerId: string,
): Promise<readonly VersionRow[]> {
  "use cache: private";
  const { organizationId, supabase } = await caller();

  const versions = await blocks(supabase, organizationId)
    .versions.list({ type: SUBJECT, id: customerId }, { pageSize: 20 })
    .orThrow();

  return versions.map((version) => ({
    id: version.id,
    number: version.number,
    label: version.label ?? null,
    source: version.source,
    createdAt: version.createdAt.epochMilliseconds,
  }));
}

/** The customer's saved versions, newest first. */
export function getVersions(customerId: string) {
  return settle(() => loadVersions(customerId));
}

export interface SlaClockRow {
  readonly id: string;
  readonly metric: "first_response" | "next_response" | "resolution";
  readonly state: "running" | "paused" | "met" | "breached";
  readonly dueAt: number;
  /** Until the due time; negative once breached, `null` once met. */
  readonly secondsLeft: number | null;
}

async function loadSlaClocks(
  customerId: string,
): Promise<readonly SlaClockRow[]> {
  "use cache: private";
  const { organizationId, supabase } = await caller();

  const clocks = await blocks(supabase, organizationId)
    .sla.clocks({ type: SUBJECT, id: customerId })
    .orThrow();

  return clocks.map((clock) => ({
    id: clock.id,
    metric: clock.metric,
    state: clock.state,
    dueAt: clock.dueAt.epochMilliseconds,
    secondsLeft: clock.secondsLeft ?? null,
  }));
}

/** The customer's SLA clocks, with the time left on each open one. */
export function getSlaClocks(customerId: string) {
  return settle(() => loadSlaClocks(customerId));
}
