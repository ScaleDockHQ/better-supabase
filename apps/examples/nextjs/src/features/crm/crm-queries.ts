import "server-only";
import type { SupplierStatus } from "better-supabase/blocks/contacts";
import type { Quote, QuoteStatus } from "better-supabase/blocks/quotes";
import type { Money } from "better-supabase/commerce";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";

import { orMissing } from "@/lib/or-missing";
import { getAllPages } from "@/lib/read-all-pages";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** A loaded region: its data, no active organization, or a failed read. */
export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "no-organization" }
  | { readonly kind: "error" };

/**
 * Runs a cached loader. A failed read throws inside the loader, so it is never
 * cached and Retry reads again.
 */
export async function settle<T>(
  load: () => Promise<T | null>,
): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

export type ContactKind = "company" | "person";

/** The records an activity timeline shows: a contact, or a care client. */
export type TimelineSubjectType = ContactKind | "customer" | "deal";

export interface ContactSummary {
  readonly id: string;
  readonly kind: ContactKind;
  readonly name: string;
  readonly lifecycle: string;
  /** A company's domain or a person's email. */
  readonly detail: string | null;
  /** Where a supplier stands, `null` until someone assesses it. */
  readonly supplierStatus: SupplierStatus | null;
}

export interface CompanyContact {
  readonly id: string;
  readonly name: string;
  readonly email: string | null;
  readonly title: string | null;
  readonly role: string | null;
  readonly primary: boolean;
}

export interface ContactDetailData extends ContactSummary {
  readonly email: string | null;
  readonly phone: string | null;
  readonly title: string | null;
  readonly domain: string | null;
  readonly website: string | null;
  /** A company's people; empty for a person. */
  readonly people: readonly CompanyContact[];
  /** People who can be added to a company; empty for a person. */
  readonly candidates: readonly ContactSummary[];
}

const PAGE = 200;

/** The first 200 companies and the first 200 people, by name. */
export async function getContacts(): Promise<readonly ContactSummary[] | null> {
  "use cache: private";
  const cached = await bsb.cached();
  cacheTag(tags.crm(), tags.customers());

  return readContacts(cached);
}

/** The same read for a function that already runs in a private scope. */
export async function readContacts({
  session,
  db,
}: Awaited<ReturnType<typeof bsb.cached>>): Promise<
  readonly ContactSummary[] | null
> {
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { contacts: parties } = db.$blocks;

  const [companies, people] = await Promise.all([
    parties.companyPage({ organizationId: tenant, limit: PAGE }).orThrow(),
    parties.personPage({ organizationId: tenant, limit: PAGE }).orThrow(),
  ]);

  return [
    ...companies.items.map((company): ContactSummary => ({
      id: company.id,
      kind: "company",
      name: company.name,
      lifecycle: company.lifecycle,
      detail: company.domain ?? null,
      supplierStatus: company.supplierStatus ?? null,
    })),
    ...people.items.map((person): ContactSummary => ({
      id: person.id,
      kind: "person",
      name: person.name,
      lifecycle: person.lifecycle,
      detail: person.email ?? null,
      supplierStatus: person.supplierStatus ?? null,
    })),
  ].toSorted((a, b) => a.name.localeCompare(b.name));
}

/** One company or person, `undefined` when it is gone or hidden. */
export async function getContact(
  id: string,
): Promise<ContactDetailData | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.crm(), tags.customers());
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { contacts: parties } = db.$blocks;

  const [companyRead, personRead] = await Promise.all([
    parties.companyById(id),
    parties.personById(id),
  ]);

  const company = orMissing(companyRead);
  const person = orMissing(personRead);

  if (company) {
    const [people, everyone] = await Promise.all([
      parties.peopleOf(company.id).orThrow(),
      parties.personPage({ organizationId: tenant, limit: PAGE }).orThrow(),
    ]);

    const linked = new Set(people.map((member) => member.id));

    return {
      id: company.id,
      kind: "company",
      name: company.name,
      lifecycle: company.lifecycle,
      detail: company.domain ?? null,
      supplierStatus: company.supplierStatus ?? null,
      email: null,
      phone: null,
      title: null,
      domain: company.domain ?? null,
      website: company.website ?? null,
      people: people.map((member) => ({
        id: member.id,
        name: member.name,
        email: member.email ?? null,
        title: member.title ?? null,
        role: member.role ?? null,
        primary: member.primary,
      })),
      candidates: everyone.items
        .filter((candidate) => !linked.has(candidate.id))
        .map((candidate) => ({
          id: candidate.id,
          kind: "person",
          name: candidate.name,
          lifecycle: candidate.lifecycle,
          detail: candidate.email ?? null,
          supplierStatus: candidate.supplierStatus ?? null,
        })),
    };
  }

  if (person) {
    return {
      id: person.id,
      kind: "person",
      name: person.name,
      lifecycle: person.lifecycle,
      detail: person.email ?? null,
      supplierStatus: person.supplierStatus ?? null,
      email: person.email ?? null,
      phone: person.phone ?? null,
      title: person.title ?? null,
      domain: null,
      website: null,
      people: [],
      candidates: [],
    };
  }

  return undefined;
}

export interface TimelineEntry {
  readonly id: string;
  readonly type: string;
  readonly title: string;
  readonly body: string | null;
  readonly outcome: string | null;
  /** ISO instant. */
  readonly createdAt: string;
  readonly overdue: boolean;
}

/** A contact's calls, emails, meetings and notes, newest first. */
export async function getTimeline(
  type: TimelineSubjectType,
  id: string,
): Promise<readonly TimelineEntry[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.crm(), tags.customers());

  if (!tenantOf(session)) {
    return null;
  }

  const entries = await db.activities
    .of({ subject: { type, id }, limit: 50 })
    .orThrow();

  return entries.map((entry) => ({
    id: entry.id,
    type: entry.type,
    title: entry.title,
    body: entry.body ?? null,
    outcome: entry.outcome ?? null,
    createdAt: entry.createdAt.toString(),
    overdue: entry.overdue,
  }));
}

export interface BoardStage {
  readonly id: string;
  readonly name: string;
  /** `open`, `won` or `lost`. */
  readonly category: string;
  readonly count: number;
  readonly totals: readonly Money[];
}

export interface BoardDeal {
  readonly id: string;
  readonly identifier: string;
  readonly name: string;
  readonly stageId: string;
  readonly daysInStage: number;
  readonly rotting: boolean;
  readonly overdue: boolean;
}

export interface DealBoardData {
  readonly pipeline: { readonly id: string; readonly name: string } | null;
  readonly stages: readonly BoardStage[];
  /** The open deals; closed stages show their count and totals only. */
  readonly deals: readonly BoardDeal[];
}

/** The default deal pipeline's columns and its open deals. */
export async function getDealBoard(): Promise<DealBoardData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.crm(), tags.customers());
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { pipelines, deals } = db;

  const all = await getAllPages((page) =>
    pipelines.page({
      organizationId: tenant,
      filters: { subjectType: ["deal"] },
      ...page,
    }),
  );

  const pipeline = all.find((item) => item.isDefault) ?? all[0];

  if (!pipeline) {
    return { pipeline: null, stages: [], deals: [] };
  }

  const [columns, positions, health] = await Promise.all([
    pipelines.board({ subjectType: "deal", pipelineId: pipeline.id }).orThrow(),
    pipelines.health(pipeline.id).orThrow(),
    deals.health(pipeline.id).orThrow(),
  ]);

  const stageOf = new Map(
    positions.map((position) => [position.subjectId, position]),
  );

  return {
    pipeline: { id: pipeline.id, name: pipeline.name },
    stages: columns.map((column) => ({
      id: column.stageId,
      name: column.name,
      category: column.category,
      count: column.count,
      totals: column.totals.map((total) => total.amount),
    })),
    deals: health.flatMap((deal) => {
      const position = stageOf.get(deal.dealId);

      return position
        ? [
            {
              id: deal.dealId,
              identifier: deal.identifier,
              name: deal.name,
              stageId: position.stageId,
              daysInStage: position.daysInStage,
              rotting: position.rotting,
              overdue: deal.overdue,
            },
          ]
        : [];
    }),
  };
}

export interface TargetRow {
  readonly id: string;
  readonly name: string;
  readonly metric: string;
  readonly currency: string | null;
  /** Minor units for amounts, a count otherwise. */
  readonly goal: bigint;
  readonly progress: bigint;
  /** Progress over the goal: 0.5 is halfway. */
  readonly attainment: number;
  readonly periodStart: string;
  readonly periodEnd: string;
}

/** The organization's targets running today, with their progress. */
export async function getTargets(): Promise<readonly TargetRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.crm(), tags.customers());
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const targets = await db.goals.progress({ organizationId: tenant }).orThrow();

  return targets.map((target) => ({
    id: target.id,
    name: target.name,
    metric: target.metric,
    currency: target.currency ?? null,
    goal: target.goal,
    progress: target.progress,
    attainment: target.attainment,
    periodStart: target.periodStart.toString(),
    periodEnd: target.periodEnd.toString(),
  }));
}

export type { QuoteStatus };

export interface QuoteLineRow {
  /** 1-based, in the order the quote lists them. */
  readonly position: number;
  readonly description: string;
  readonly quantity: number;
  readonly unitAmount: Money;
  readonly discountBps: number;
  readonly taxRateBps: number;
}

export interface QuoteDetailData {
  readonly id: string;
  readonly identifier: string;
  readonly revision: number;
  readonly title: string;
  readonly status: QuoteStatus;
  readonly currency: string;
  readonly validUntil: string | null;
  readonly lines: readonly QuoteLineRow[];
  readonly subtotal: Money;
  readonly discountTotal: Money;
  readonly taxTotal: Money;
  readonly total: Money;
}

function quoteOf(quote: Quote): QuoteDetailData {
  return {
    id: quote.id,
    identifier: quote.identifier,
    revision: quote.revision,
    title: quote.title,
    status: quote.status,
    currency: quote.currency,
    validUntil: quote.validUntil?.toString() ?? null,
    lines: quote.lines.map((line) => ({
      position: line.position,
      description: line.description,
      quantity: line.quantity,
      unitAmount: line.unitAmount,
      discountBps: line.discountBps,
      taxRateBps: line.taxRateBps,
    })),
    subtotal: quote.totals.subtotal,
    discountTotal: quote.totals.discountTotal,
    taxTotal: quote.totals.taxTotal,
    total: quote.totals.total,
  };
}

/** One quote, `undefined` when it is gone. */
export async function getQuote(
  id: string,
): Promise<QuoteDetailData | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.crm(), tags.customers());

  if (!tenantOf(session)) {
    return null;
  }

  const quote = orMissing(await db.$blocks.quotes.get(id));

  return quote ? quoteOf(quote) : undefined;
}
