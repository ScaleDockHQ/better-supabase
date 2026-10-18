import "server-only";
import type { Money } from "better-supabase/commerce";

import { money } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/** A loaded region: its data, no active organization, or a failed read. */
export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "no-organization" }
  | { readonly kind: "error" };

/**
 * Runs a cached loader. A failed read throws inside the loader, so it is
 * never cached and Retry reads again.
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

export interface ContactSummary {
  readonly id: string;
  readonly kind: ContactKind;
  readonly name: string;
  readonly lifecycle: string;
  /** A company's domain or a person's email. */
  readonly detail: string | null;
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

/** How many pages `loadContact` scans before it calls a contact missing. */
const MAX_PAGES = 10;

/** The first 200 companies and the first 200 people, by name. */
export async function loadContacts(): Promise<
  readonly ContactSummary[] | null
> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { parties } = blocks(supabase);

  const [companies, people] = await Promise.all([
    parties.listCompanies(tenant, { limit: PAGE }).orThrow(),
    parties.listPeople(tenant, { limit: PAGE }).orThrow(),
  ]);

  return [
    ...companies.items.map((company): ContactSummary => ({
      id: company.id,
      kind: "company",
      name: company.name,
      lifecycle: company.lifecycle,
      detail: company.domain ?? null,
    })),
    ...people.items.map((person): ContactSummary => ({
      id: person.id,
      kind: "person",
      name: person.name,
      lifecycle: person.lifecycle,
      detail: person.email ?? null,
    })),
  ].toSorted((a, b) => a.name.localeCompare(b.name));
}

/**
 * One company or person, `undefined` when it is gone or hidden. The parties
 * block has no read by id, so this pages through the lists by name.
 */
export async function loadContact(
  id: string,
): Promise<ContactDetailData | undefined | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { parties } = blocks(supabase);
  let companyCursor: { name: string; id: string } | undefined;

  for (let page = 0; page < MAX_PAGES; page += 1) {
    const companies = await parties
      .listCompanies(
        tenant,
        companyCursor
          ? { limit: PAGE, cursor: companyCursor }
          : { limit: PAGE },
      )
      .orThrow();

    const company = companies.items.find((item) => item.id === id);

    if (company) {
      const [people, everyone] = await Promise.all([
        parties.peopleOf(company.id).orThrow(),
        parties.listPeople(tenant, { limit: PAGE }).orThrow(),
      ]);

      const linked = new Set(people.map((person) => person.id));

      return {
        id: company.id,
        kind: "company",
        name: company.name,
        lifecycle: company.lifecycle,
        detail: company.domain ?? null,
        email: null,
        phone: null,
        title: null,
        domain: company.domain ?? null,
        website: company.website ?? null,
        people: people.map((person) => ({
          id: person.id,
          name: person.name,
          email: person.email ?? null,
          title: person.title ?? null,
          role: person.role ?? null,
          primary: person.primary,
        })),
        candidates: everyone.items
          .filter((person) => !linked.has(person.id))
          .map((person) => ({
            id: person.id,
            kind: "person",
            name: person.name,
            lifecycle: person.lifecycle,
            detail: person.email ?? null,
          })),
      };
    }

    if (!companies.next) {
      break;
    }

    companyCursor = companies.next;
  }

  let personCursor: { name: string; id: string } | undefined;

  for (let page = 0; page < MAX_PAGES; page += 1) {
    const people = await parties
      .listPeople(
        tenant,
        personCursor ? { limit: PAGE, cursor: personCursor } : { limit: PAGE },
      )
      .orThrow();

    const person = people.items.find((item) => item.id === id);

    if (person) {
      return {
        id: person.id,
        kind: "person",
        name: person.name,
        lifecycle: person.lifecycle,
        detail: person.email ?? null,
        email: person.email ?? null,
        phone: person.phone ?? null,
        title: person.title ?? null,
        domain: null,
        website: null,
        people: [],
        candidates: [],
      };
    }

    if (!people.next) {
      break;
    }

    personCursor = people.next;
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
export async function loadTimeline(
  type: ContactKind,
  id: string,
): Promise<readonly TimelineEntry[] | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const entries = await blocks(supabase)
    .engagements.of({ type, id }, { limit: 50 })
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
export async function loadDealBoard(): Promise<DealBoardData | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { pipelines, deals } = blocks(supabase);
  const all = await pipelines.list(tenant, "deal").orThrow();
  const pipeline = all.find((item) => item.isDefault) ?? all[0];

  if (!pipeline) {
    return { pipeline: null, stages: [], deals: [] };
  }

  const [columns, positions, health] = await Promise.all([
    pipelines.board("deal", pipeline.id).orThrow(),
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
export async function loadTargets(): Promise<readonly TargetRow[] | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const targets = await blocks(supabase).targets.progress(tenant).orThrow();

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

const Amount = v.union([v.string(), v.number()]);

const QuoteRow = v.object({
  id: v.string(),
  identifier: v.string(),
  revision: v.number(),
  title: v.string(),
  status: v.picklist([
    "draft",
    "sent",
    "viewed",
    "accepted",
    "rejected",
    "changes_requested",
    "expired",
    "withdrawn",
  ]),
  currency: v.string(),
  valid_until: v.nullish(v.string()),
  total: Amount,
  subtotal: Amount,
  discount_total: Amount,
  tax_total: Amount,
  list_total: Amount,
  lines: v.nullish(
    v.array(
      v.object({
        description: v.string(),
        quantity: v.nullish(v.number()),
        unitAmount: Amount,
        discountBps: v.nullish(v.number()),
        taxRateBps: v.nullish(v.number()),
      }),
    ),
  ),
});

export type QuoteStatus = v.InferOutput<typeof QuoteRow>["status"];

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

function quoteOf(row: v.InferOutput<typeof QuoteRow>): QuoteDetailData {
  const at = (amount: string | number) => money(BigInt(amount), row.currency);

  return {
    id: row.id,
    identifier: row.identifier,
    revision: row.revision,
    title: row.title,
    status: row.status,
    currency: row.currency,
    validUntil: row.valid_until ?? null,
    lines: (row.lines ?? []).map((line, index) => ({
      position: index + 1,
      description: line.description,
      quantity: line.quantity ?? 1,
      unitAmount: at(line.unitAmount),
      discountBps: line.discountBps ?? 0,
      taxRateBps: line.taxRateBps ?? 0,
    })),
    subtotal: at(row.subtotal),
    discountTotal: at(row.discount_total),
    taxTotal: at(row.tax_total),
    total: at(row.total),
  };
}

/**
 * The organization's latest quotes. The quotes block has no read function
 * yet: this calls `api.list_quotes(tenant, page_size)`, which the library
 * still has to add, so the region shows its error state until then.
 */
export async function loadQuotes(): Promise<readonly QuoteDetailData[] | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const rows = await blocks(supabase).call("list_quotes", {
    tenant,
    page_size: 50,
  });

  return v.parse(v.array(QuoteRow), rows).map(quoteOf);
}

/** One quote, `undefined` when it is gone. Calls `api.get_quote(quote)`, see `loadQuotes`. */
export async function loadQuote(
  id: string,
): Promise<QuoteDetailData | undefined | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const row = v.parse(
    v.nullish(QuoteRow),
    await blocks(supabase).call("get_quote", { quote: id }),
  );

  return row ? quoteOf(row) : undefined;
}
