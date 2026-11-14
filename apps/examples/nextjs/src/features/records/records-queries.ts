import "server-only";
import type { RecordBindingResult } from "better-supabase/records";

import { toDbError } from "better-supabase";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import { Temporal } from "temporal-polyfill";

import { customerPage } from "@/features/customers/customer-record";
import { getMembers } from "@/features/organization/organization-queries";
import { loadDeals } from "@/features/sales/pipeline/pipeline-queries";
import { getSession } from "@/features/user/user-queries";
import { bsb } from "@/lib/supabase/server";

import type { RecordSubject } from "./record-subject";

import { recordPages } from "./record-pages";

/**
 * What a card on a record page renders: the rows, or a failed read. The page
 * renders no card for a hidden binding.
 */
export type Loaded<T> = Exclude<
  RecordBindingResult<T>,
  { readonly kind: "hidden" }
>;

/** A hidden binding reads as an empty list on the cards that always render. */
export function visible<T>(
  result: RecordBindingResult<readonly T[]>,
): Loaded<readonly T[]> {
  return result.kind === "hidden" ? { kind: "ok", data: [] } : result;
}

export function mapped<T, U>(
  result: RecordBindingResult<readonly T[]>,
  map: (row: T) => U,
): RecordBindingResult<readonly U[]> {
  return result.kind === "ok"
    ? { kind: "ok", data: result.data.map(map) }
    : result;
}

export const epoch = (iso: string): number =>
  Temporal.Instant.from(iso).epochMilliseconds;

export const epochOrNull = (iso: string | null | undefined): number | null =>
  iso === null || iso === undefined ? null : epoch(iso);

export interface AttachmentRow {
  readonly id: string;
  readonly name: string;
  readonly size: number;
  readonly status: "pending" | "clean" | "infected" | "failed";
  /** `false` until the browser finished the upload and it was confirmed. */
  readonly uploaded: boolean;
  readonly createdAt: number;
}

/** The record's files, newest first. */
export async function getAttachments(
  subject: RecordSubject,
): Promise<RecordBindingResult<readonly AttachmentRow[]>> {
  const { bindings } = await recordPages[subject.type].load(subject.id, {
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

export interface RecordOption {
  readonly id: string;
  readonly name: string;
}

export interface RelatedRecord {
  readonly id: string;
  /** The kind as read from this record's side, such as `relates`. */
  readonly kind: string;
  readonly subjectType: string;
  readonly subjectId: string;
}

export interface Relations {
  readonly links: readonly RelatedRecord[];
  /** The other records of the same type the picker offers, by name. */
  readonly options: readonly RecordOption[];
}

const OPTION_LIMIT = 200;

/** The records of `subject`'s type a link can point to, by name. */
async function relationOptions(
  subject: RecordSubject,
): Promise<readonly RecordOption[]> {
  const [{ db }, session] = await Promise.all([bsb.context(), getSession()]);
  const tenant = tenantOf(session);

  const named = (rows: readonly RecordOption[]): readonly RecordOption[] =>
    rows
      .filter((row) => row.id !== subject.id)
      .map((row) => ({ id: row.id, name: row.name }));

  switch (subject.type) {
    case "customer": {
      return named(
        await db.customers
          .list({
            select: ["id", "name"],
            orderBy: { name: "asc" },
            limit: OPTION_LIMIT,
          })
          .orThrow(),
      );
    }

    case "company": {
      return tenant
        ? named(
            (
              await db.$blocks.contacts
                .listCompanies({ organizationId: tenant, limit: OPTION_LIMIT })
                .orThrow()
            ).items,
          )
        : [];
    }

    case "person": {
      return tenant
        ? named(
            (
              await db.$blocks.contacts
                .listPeople({ organizationId: tenant, limit: OPTION_LIMIT })
                .orThrow()
            ).items,
          )
        : [];
    }

    case "deal": {
      const deals = await loadDeals();

      return named(deals?.deals ?? []);
    }

    default: {
      const unreachable: never = subject.type;

      return unreachable;
    }
  }
}

/** The records linked to the record, and the records it can link to. */
export async function getRelations(
  subject: RecordSubject,
): Promise<Loaded<Relations>> {
  const { bindings } = await recordPages[subject.type].load(subject.id, {
    bindings: ["relations"],
  });

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
    return {
      kind: "ok",
      data: { links: links.data, options: await relationOptions(subject) },
    };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error", error: toDbError(error) };
  }
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
 * The record's latest comments, files and versions in one list, newest first. A
 * failed binding fails the card only when nothing else loaded.
 */
export async function getTimeline(
  subject: RecordSubject,
): Promise<Loaded<readonly TimelineRow[]>> {
  // A customer also has versions, so its page merges one more binding.
  const timeline =
    subject.type === "customer"
      ? await customerPage.timeline(subject.id, { limit: TIMELINE_LIMIT })
      : await recordPages[subject.type].timeline(subject.id, {
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

/** Display names by user id, for the people who wrote on a record. */
export async function getAuthors(): Promise<Readonly<Record<string, string>>> {
  const session = await getSession();
  const tenant = tenantOf(session);

  if (!tenant) {
    return {};
  }

  const members = await getMembers(tenant);

  return Object.fromEntries(
    members.flatMap((member) => {
      const name = member.name ?? member.email;

      return name ? [[member.userId, name]] : [];
    }),
  );
}
