import "server-only";
import type { RecordBindingResult } from "better-supabase/records";

import { toDbError } from "better-supabase";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import { cache } from "react";
import { Temporal } from "temporal-polyfill";

import type { ConversationRow } from "@/features/inbox/inbox-types";

import { customerPage } from "@/features/customers/customer-record";
import { toConversationRow } from "@/features/inbox/inbox-types";
import { getMembers } from "@/features/organization/organization-queries";
import {
  loadDirectory,
  getHiringBoard,
} from "@/features/people/people-queries";
import { getDeals } from "@/features/sales/pipeline/pipeline-queries";
import { getOrders, getProducts } from "@/features/shop/shop-queries";
import { getSession } from "@/features/user/user-queries";
import { bsb } from "@/lib/supabase/server";

import type { RecordSubject, RecordType } from "./record-subject";

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

/** A binding the shared record sections read. */
export type SectionBinding =
  | "attachments"
  | "customFields"
  | "relations"
  | "tags";

const SECTION_BINDINGS: readonly SectionBinding[] = [
  "attachments",
  "customFields",
  "relations",
  "tags",
];

/**
 * A record with the bindings its page shows (`RecordBoundSections` sets them),
 * so the sections share one `get` instead of one each.
 */
export interface SectionSubject extends RecordSubject {
  readonly bindings?: readonly SectionBinding[];
}

/**
 * The bindings in `key` (comma separated), loaded once per record, set and
 * request: one `get`, whose reads go to the database as one `read_batch` call.
 * A section the caller can't read comes back `hidden` without a query.
 */
const getBindingSet = cache(
  async (type: RecordType, id: string, key: string) => {
    const wanted = new Set(key.split(","));

    const { bindings } = await recordPages[type].get(id, {
      bindings: SECTION_BINDINGS.filter((binding) => wanted.has(binding)),
    });

    return bindings;
  },
);

/**
 * Every binding the customer page shows, its own and the shared sections', in
 * one `get` per request.
 */
export const getCustomerBindings = cache(async (customerId: string) => {
  const { bindings } = await customerPage.get(customerId, {
    bindings: ["attachments", "relations", "shareLinks", "versions", "sla"],
    options: { versions: { pageSize: 20 } },
  });

  return bindings;
});

/**
 * The shared sections' bindings of `subject`: `binding` and the others its page
 * shows, from one `get`.
 */
export function getSectionBindings(
  subject: SectionSubject,
  binding: SectionBinding,
) {
  const wanted = subject.bindings?.includes(binding)
    ? new Set(subject.bindings)
    : new Set([binding]);

  return getBindingSet(
    subject.type,
    subject.id,
    SECTION_BINDINGS.filter((name) => wanted.has(name)).join(","),
  );
}

/** The record's files, newest first. */
export async function getAttachments(
  subject: RecordSubject,
): Promise<RecordBindingResult<readonly AttachmentRow[]>> {
  const { attachments } =
    subject.type === "customer"
      ? await getCustomerBindings(subject.id)
      : await getSectionBindings(subject, "attachments");

  return mapped(attachments, (file) => ({
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
                .companyPage({ organizationId: tenant, limit: OPTION_LIMIT })
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
                .personPage({ organizationId: tenant, limit: OPTION_LIMIT })
                .orThrow()
            ).items,
          )
        : [];
    }

    case "deal": {
      const deals = await getDeals();

      return named(deals?.deals ?? []);
    }

    case "contract": {
      return tenant
        ? named(
            (
              await db.contracts
                .page({ organizationId: tenant, limit: OPTION_LIMIT })
                .orThrow()
            ).items.map((contract) => ({
              id: contract.id,
              name: contract.title,
            })),
          )
        : [];
    }

    // Service and logistics
    case "work_order": {
      return named(
        (await db.dispatch.page({ limit: OPTION_LIMIT }).orThrow()).items.map(
          (order) => ({ id: order.id, name: order.title }),
        ),
      );
    }

    case "shipment": {
      return named(
        (
          await db.shipments.shipmentPage({ limit: OPTION_LIMIT }).orThrow()
        ).items.map((shipment) => ({
          id: shipment.id,
          name: shipment.reference,
        })),
      );
    }

    // Support
    case "case": {
      return named(
        (await db.cases.page({ limit: OPTION_LIMIT }).orThrow()).items.map(
          (item) => ({ id: item.id, name: `${item.number} ${item.title}` }),
        ),
      );
    }

    case "content_entry": {
      return named(
        (await db.content.page({ limit: OPTION_LIMIT }).orThrow()).items.map(
          (entry) => ({ id: entry.id, name: entry.title }),
        ),
      );
    }

    case "meeting": {
      return named(
        (await db.meetings.page({ limit: OPTION_LIMIT }).orThrow()).items.map(
          (meeting) => ({ id: meeting.id, name: meeting.title }),
        ),
      );
    }

    case "care_plan": {
      return named(
        (await db.carePlans.page({ limit: OPTION_LIMIT }).orThrow()).items.map(
          (plan) => ({ id: plan.id, name: plan.title }),
        ),
      );
    }

    case "risk": {
      return named(
        (await db.risks.page({ limit: OPTION_LIMIT }).orThrow()).items.map(
          (risk) => ({ id: risk.id, name: `${risk.number} ${risk.title}` }),
        ),
      );
    }

    case "vulnerability": {
      return tenant
        ? named(
            (
              await db.advisories
                .pageVulnerabilities({
                  organizationId: tenant,
                  limit: OPTION_LIMIT,
                })
                .orThrow()
            ).items.map((vulnerability) => ({
              id: vulnerability.id,
              name: vulnerability.vulnId,
            })),
          )
        : [];
    }

    // People
    case "employee": {
      const directory = await loadDirectory();

      return named(
        (directory?.managers ?? []).map((manager) => ({
          id: manager.value,
          name: manager.label,
        })),
      );
    }

    case "application": {
      const board = await getHiringBoard();

      return named(board?.cards ?? []);
    }

    case "course": {
      return named(
        (await db.courses.list({ limit: OPTION_LIMIT }).orThrow()).map(
          (course) => ({ id: course.id, name: course.title }),
        ),
      );
    }

    case "order": {
      const orders = await getOrders();

      return orders.kind === "ok"
        ? named(
            orders.data.orders.map((order) => ({
              id: order.id,
              name: order.number,
            })),
          )
        : [];
    }

    case "invoice": {
      return tenant
        ? named(
            (
              await db.invoices
                .page({ organizationId: tenant, limit: OPTION_LIMIT })
                .orThrow()
            ).items.map((invoice) => ({
              id: invoice.id,
              name: String(invoice.number ?? invoice.id),
            })),
          )
        : [];
    }

    case "production_order": {
      return tenant
        ? named(
            (
              await db.manufacturing
                .orderPage({ limit: OPTION_LIMIT })
                .orThrow()
            ).items.map((order) => ({ id: order.id, name: order.number })),
          )
        : [];
    }

    case "inspection": {
      return tenant
        ? named(
            (
              await db.inspections.page({ limit: OPTION_LIMIT }).orThrow()
            ).items.map((inspection) => ({
              id: inspection.id,
              name: inspection.title,
            })),
          )
        : [];
    }

    case "product": {
      const products = await getProducts();

      return products.kind === "ok"
        ? named(
            products.data.map((product) => ({
              id: product.id,
              name: product.title,
            })),
          )
        : [];
    }

    case "till": {
      return tenant
        ? named(
            (
              await db.tills.tillPage({ limit: OPTION_LIMIT }).orThrow()
            ).items.map((till) => ({ id: till.id, name: till.name })),
          )
        : [];
    }

    default: {
      const unreachable: never = subject.type;

      return unreachable;
    }
  }
}

/** The records linked to the record. */
async function getLinks(
  subject: RecordSubject,
): Promise<Loaded<readonly RelatedRecord[]>> {
  const { relations } =
    subject.type === "customer"
      ? await getCustomerBindings(subject.id)
      : await getSectionBindings(subject, "relations");

  return visible(
    mapped(relations, (link) => ({
      id: link.id,
      kind: link.kind,
      subjectType: link.subject.type,
      subjectId: link.subject.id,
    })),
  );
}

/** The records linked to the record, and the records it can link to. */
export async function getRelations(
  subject: RecordSubject,
): Promise<Loaded<Relations>> {
  const links = await getLinks(subject);

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

/** The newest conversations the lookup reads, across every status. */
const CONVERSATION_WINDOW = 50;

/**
 * The inbox conversations of the people on the record: the record itself when
 * it is a person, otherwise the people on its relations binding. The inbox
 * lists by tenant, so the newest ones are filtered to those people.
 */
export async function getRecordConversations(
  subject: RecordSubject,
): Promise<readonly ConversationRow[]> {
  const [{ db }, session] = await Promise.all([bsb.context(), getSession()]);
  const tenant = tenantOf(session);

  if (!tenant) {
    return [];
  }

  const people = new Set<string>(subject.type === "person" ? [subject.id] : []);

  if (subject.type !== "person") {
    const links = await getLinks(subject);

    if (links.kind === "ok") {
      for (const link of links.data) {
        if (link.subjectType === "person") {
          people.add(link.subjectId);
        }
      }
    }
  }

  if (people.size === 0) {
    return [];
  }

  const { items } = await db.inbox.conversations
    .page({
      organizationId: tenant,
      filters: { status: ["all"] },
      limit: CONVERSATION_WINDOW,
    })
    .orThrow();

  return items
    .filter((conversation) => people.has(conversation.contactId))
    .map(toConversationRow);
}

/** The newest workflow runs started for one record. */
export async function getRecordRuns(subject: RecordSubject) {
  const [{ db }, session] = await Promise.all([bsb.context(), getSession()]);
  const tenant = tenantOf(session);

  if (!tenant) {
    return [];
  }

  return db.workflows.runs
    .list({ tenant, subject, mode: "all", limit: 10 })
    .orThrow();
}

export interface RecordTaskRow {
  readonly id: string;
  readonly title: string;
  readonly status: "todo" | "doing" | "done";
  /** `YYYY-MM-DD`, or null when unscheduled. */
  readonly dueOn: string | null;
}

const RECORD_TASK_LIMIT = 10;

/** The tasks linked to the record through its relations, in rank order. */
export async function getRecordTasks(
  subject: RecordSubject,
): Promise<readonly RecordTaskRow[]> {
  const [{ db }, links] = await Promise.all([bsb.context(), getLinks(subject)]);

  if (links.kind !== "ok") {
    return [];
  }

  const ids = links.data
    .filter((link) => link.subjectType === "task")
    .map((link) => link.subjectId)
    .slice(0, RECORD_TASK_LIMIT);

  if (ids.length === 0) {
    return [];
  }

  return db.tasks
    .list({
      select: ["id", "title", "status", "dueOn"],
      where: { id: { in: ids } },
      orderBy: { rank: "asc" },
      limit: RECORD_TASK_LIMIT,
    })
    .orThrow();
}
