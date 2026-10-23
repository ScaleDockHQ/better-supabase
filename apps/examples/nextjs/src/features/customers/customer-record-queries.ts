import "server-only";
import type { RecordBindingResult } from "better-supabase/records";

import { toDbError } from "better-supabase";
import { unstable_rethrow } from "next/navigation";
import { Temporal } from "temporal-polyfill";

import { bsb } from "@/lib/supabase/server";

import { customerPage } from "./customer-record";

/**
 * What a card on the customer page renders: the rows, or a failed read. The
 * page renders no card for a hidden binding.
 */
export type Loaded<T> = Exclude<
  RecordBindingResult<T>,
  { readonly kind: "hidden" }
>;

/** A hidden binding reads as an empty list on the cards that always render. */
function visible<T>(
  result: RecordBindingResult<readonly T[]>,
): Loaded<readonly T[]> {
  return result.kind === "hidden" ? { kind: "ok", data: [] } : result;
}

function mapped<T, U>(
  result: RecordBindingResult<readonly T[]>,
  map: (row: T) => U,
): RecordBindingResult<readonly U[]> {
  return result.kind === "ok"
    ? { kind: "ok", data: result.data.map(map) }
    : result;
}

const epoch = (iso: string): number =>
  Temporal.Instant.from(iso).epochMilliseconds;

const epochOrNull = (iso: string | null | undefined): number | null =>
  iso === null || iso === undefined ? null : epoch(iso);

export interface ShareLinkRow {
  readonly id: string;
  readonly role: string;
  /** Epoch milliseconds; `null` for a link without an expiry. */
  readonly expiresAt: number | null;
  readonly revokedAt: number | null;
  /** Past its expiry when the list was read. */
  readonly expired: boolean;
}

/** The share links the caller created or may read, revoked ones last. */
export async function getShareLinks(
  customerId: string,
): Promise<Loaded<readonly ShareLinkRow[]>> {
  const { bindings } = await customerPage.load(customerId, {
    bindings: ["shareLinks"],
  });

  const now = Temporal.Now.instant().epochMilliseconds;

  return visible(
    mapped(bindings.shareLinks, (link) => {
      const expiresAt = epochOrNull(link.expiresAt);

      return {
        id: link.id,
        role: link.role,
        expiresAt,
        revokedAt: epochOrNull(link.revokedAt),
        expired: expiresAt !== null && expiresAt <= now,
      };
    }),
  );
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

/** The customer's files, newest first. */
export async function getAttachments(
  customerId: string,
): Promise<RecordBindingResult<readonly AttachmentRow[]>> {
  const { bindings } = await customerPage.load(customerId, {
    bindings: ["attachments"],
  });

  return mapped(bindings.attachments, (file) => ({
    id: file.id,
    name: file.name,
    size: file.size,
    status: file.status,
    uploaded: file.uploadedAt !== undefined,
    createdAt: epoch(file.createdAt),
  }));
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

/** The records linked to the customer, and the customers it can link to. */
export async function getRelations(
  customerId: string,
): Promise<Loaded<Relations>> {
  const [{ bindings }, { db }] = await Promise.all([
    customerPage.load(customerId, { bindings: ["relations"] }),
    bsb.context(),
  ]);

  const links = visible(
    mapped(bindings.relations, (link) => ({
      id: link.id,
      kind: link.kind,
      subjectType: link.subject.type,
      subjectId: link.subject.id,
    })),
  );

  if (links.kind === "error") {
    return links;
  }

  try {
    const customers = await db.customers
      .list({ select: ["id", "name"], orderBy: { name: "asc" }, limit: 200 })
      .orThrow();

    return {
      kind: "ok",
      data: {
        links: links.data,
        options: customers.filter((row) => row.id !== customerId),
      },
    };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error", error: toDbError(error) };
  }
}

export interface VersionRow {
  readonly id: string;
  readonly number: number;
  readonly label: string | null;
  readonly source: "manual" | "auto" | "restore";
  readonly createdAt: number;
}

/** The customer's saved versions, newest first. */
export async function getVersions(
  customerId: string,
): Promise<Loaded<readonly VersionRow[]>> {
  const { bindings } = await customerPage.load(customerId, {
    bindings: ["versions"],
    options: { versions: { pageSize: 20 } },
  });

  return visible(
    mapped(bindings.versions, (version) => ({
      id: version.id,
      number: version.number,
      label: version.label ?? null,
      source: version.source,
      createdAt: epoch(version.createdAt),
    })),
  );
}

export interface SlaClockRow {
  readonly id: string;
  readonly metric: "first_response" | "next_response" | "resolution";
  readonly state: "running" | "paused" | "met" | "breached";
  readonly dueAt: number;
  /** Until the due time; negative once breached, `null` once met. */
  readonly secondsLeft: number | null;
}

/** The customer's SLA clocks, with the time left on each open one. */
export async function getSlaClocks(
  customerId: string,
): Promise<Loaded<readonly SlaClockRow[]>> {
  const { bindings } = await customerPage.load(customerId, {
    bindings: ["sla"],
  });

  return visible(
    mapped(bindings.sla, (clock) => ({
      id: clock.id,
      metric: clock.metric,
      state: clock.state,
      dueAt: epoch(clock.dueAt),
      secondsLeft: clock.secondsLeft ?? null,
    })),
  );
}

export interface TimelineRow {
  readonly id: string;
  readonly kind: "comment" | "attachment" | "version" | (string & {});
  /** Epoch milliseconds. */
  readonly at: number;
  readonly actor: string | null;
}

const TIMELINE_LIMIT = 20;

/**
 * The customer's latest comments, files and versions in one list, newest first.
 * A failed binding fails the card only when nothing else loaded.
 */
export async function getTimeline(
  customerId: string,
): Promise<Loaded<readonly TimelineRow[]>> {
  const timeline = await customerPage.timeline(customerId, {
    limit: TIMELINE_LIMIT,
  });

  const failed = Object.values(timeline.skipped).find(
    (result) => result.kind === "error",
  );

  if (failed?.kind === "error" && timeline.entries.length === 0) {
    return failed;
  }

  return {
    kind: "ok",
    data: timeline.entries.map((entry) => ({
      id: `${entry.binding}:${entry.id}`,
      kind: entry.kind,
      at: epoch(entry.at),
      actor: entry.actor ?? null,
    })),
  };
}
