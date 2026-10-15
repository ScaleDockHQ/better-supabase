import type { SubjectConfig } from "../../config/types/subjects.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** How a rep calls a deal for the period. `undefined` is "not called". */
export type ForecastCategory = "commit" | "best_case" | "pipeline" | "omit";

export type DealOutcome = "open" | "won" | "lost";

const OUTCOMES: readonly DealOutcome[] = ["open", "won", "lost"];
const FORECASTS: readonly ForecastCategory[] = [
  "commit",
  "best_case",
  "pipeline",
  "omit",
];

/** A record a deal points at: its company or a contact. */
export interface DealParty {
  readonly type: string;
  readonly id: string;
}

export interface DealContact extends DealParty {
  readonly role?: string;
  readonly primary: boolean;
}

export interface Deal {
  readonly id: string;
  readonly organizationId: string;
  readonly number: bigint;
  /** `DEAL-4821`, or the number-sequences format. */
  readonly identifier: string;
  readonly name: string;
  readonly company?: DealParty;
  readonly ownerId?: string;
  /** `new_logo`, `expansion`, `renewal` or a configured motion. */
  readonly motion?: string;
  /** `hot`, `warm`, `cold` or a configured priority. */
  readonly priority?: string;
  readonly product?: string;
  readonly seats?: number;
  /** Minor units. */
  readonly amount: bigint;
  /** The revenue the account already brings, for an expansion. Minor units. */
  readonly existingAmount: bigint;
  readonly currency: string;
  readonly valuePeriod: "one_time" | "monthly" | "annual";
  /** `line_items` keeps the amount equal to the lines' subtotal. */
  readonly amountSource: "manual" | "line_items";
  readonly pipelineId?: string;
  readonly stageId?: string;
  readonly stageEnteredAt?: Temporal.Instant;
  readonly outcome: DealOutcome;
  /** The deal's own win probability; the stage's applies without it. */
  readonly probability?: number;
  readonly forecast?: ForecastCategory;
  readonly openedOn: Temporal.PlainDate;
  readonly closeOn: Temporal.PlainDate;
  /** The first close date, set the first time the close date moved later. */
  readonly slippedFrom?: Temporal.PlainDate;
  /** How often the close date moved later. */
  readonly pushCount: number;
  readonly closedAt?: Temporal.Instant;
  readonly nextStep?: string;
  readonly nextAt?: Temporal.Instant;
  readonly nextKind?: string;
  readonly flags: readonly string[];
  readonly source?: string;
  readonly note?: string;
  readonly lostReason?: string;
  /** A locked deal takes only its note. */
  readonly locked: boolean;
  readonly rank: string;
  readonly totals: DealTotals;
  readonly contacts: readonly DealContact[];
  readonly members: readonly {
    readonly userId: string;
    readonly role?: string;
  }[];
  /** The app's extra columns, by column name. */
  readonly fields: Readonly<Record<string, unknown>>;
  readonly archived: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** Line totals in minor units: list, discount, subtotal, tax and total. */
export interface DealTotals {
  readonly listTotal: bigint;
  readonly discountTotal: bigint;
  readonly subtotal: bigint;
  readonly taxTotal: bigint;
  readonly total: bigint;
}

export interface DealInput {
  readonly name: string;
  readonly closeOn: Temporal.PlainDate;
  readonly amount?: bigint;
  readonly currency?: string;
  readonly company?: DealParty;
  readonly ownerId?: string;
  readonly motion?: string;
  readonly priority?: string;
  readonly product?: string;
  readonly seats?: number;
  readonly existingAmount?: bigint;
  readonly valuePeriod?: Deal["valuePeriod"];
  readonly pipelineId?: string;
  readonly stageId?: string;
  readonly probability?: number;
  readonly forecast?: ForecastCategory;
  readonly nextStep?: string;
  readonly nextAt?: Temporal.Instant;
  readonly nextKind?: string;
  readonly flags?: readonly string[];
  readonly source?: string;
  readonly note?: string;
}

/** The fields `update` writes, the shape of a grid cell edit. */
export type DealField =
  | "name"
  | "motion"
  | "priority"
  | "ownerId"
  | "product"
  | "seats"
  | "amount"
  | "existingAmount"
  | "currency"
  | "valuePeriod"
  | "amountSource"
  | "stageId"
  | "probability"
  | "forecast"
  | "closeOn"
  | "nextStep"
  | "nextAt"
  | "nextKind"
  | "flags"
  | "source"
  | "note"
  | "lostReason"
  | "company";

/** One cell edit. `null` clears the field. */
export interface DealChange {
  readonly dealId: string;
  readonly field: DealField;
  readonly value: unknown;
}

export interface DealChangeResult {
  readonly accepted: readonly {
    readonly dealId: string;
    readonly field: string;
  }[];
  /** Each refused change, with the error hint and message. Others still applied. */
  readonly rejected: readonly {
    readonly dealId: string;
    readonly field: string;
    readonly hint?: string;
    readonly reason: string;
  }[];
}

/** A line of a deal. Amounts are minor units. */
export interface DealLineInput {
  readonly description: string;
  readonly quantity?: number;
  readonly unitAmount: bigint;
  readonly discountBps?: number;
  readonly taxRateBps?: number;
  readonly taxCode?: string;
  readonly product?: DealParty;
}

/** The forecast call for one currency. Amounts are minor units. */
export interface DealForecast {
  readonly currency: string;
  readonly won: bigint;
  readonly commit: bigint;
  readonly bestCase: bigint;
  readonly pipeline: bigint;
  readonly notCalled: bigint;
  readonly omit: bigint;
  /** Open deals that close after the period. */
  readonly later: bigint;
  readonly target?: bigint;
  /** Won plus commit over the target. */
  readonly attainment?: number;
  readonly gap?: bigint;
  readonly owners: readonly (Omit<
    DealForecast,
    "owners" | "currency" | "target" | "attainment" | "gap"
  > & {
    readonly ownerId?: string;
  })[];
}

/** The checks a forecast review runs on an open deal. */
export interface DealHealth {
  readonly dealId: string;
  readonly identifier: string;
  readonly name: string;
  readonly daysInStage: number;
  readonly rotting: boolean;
  /** The close date moved later or passed. */
  readonly slipped: boolean;
  readonly noNextStep: boolean;
  readonly overdue: boolean;
}

export interface Deals {
  create(
    organizationId: string,
    input: DealInput,
    contacts?: readonly DealContact[],
  ): AsyncResult<Deal>;
  /** Applies cell edits; a refused change leaves the others applied. */
  update(changes: readonly DealChange[]): AsyncResult<DealChangeResult>;
  /** Moves the deal to its pipeline's won stage. `note` is the closing note. */
  win(dealId: string, note?: string): AsyncResult<Deal>;
  /** Moves the deal to its pipeline's lost stage. */
  lose(dealId: string, reason?: string): AsyncResult<Deal>;
  /** Opens a closed deal again, in `stageId` or the first open stage. */
  reopen(dealId: string, stageId?: string): AsyncResult<Deal>;
  setContacts(
    dealId: string,
    contacts: readonly DealContact[],
  ): AsyncResult<number>;
  /** Replaces the deal team; each member watches the deal. */
  setMembers(
    dealId: string,
    members: readonly { readonly userId: string; readonly role?: string }[],
  ): AsyncResult<number>;
  setLines(
    dealId: string,
    lines: readonly DealLineInput[],
  ): AsyncResult<DealTotals>;
  archive(dealId: string, archived?: boolean): AsyncResult<boolean>;
  remove(dealId: string): AsyncResult<boolean>;
  forecast(
    organizationId: string,
    period: {
      readonly since: Temporal.PlainDate;
      readonly until: Temporal.PlainDate;
      readonly currency: string;
      readonly target?: bigint;
      readonly pipelineId?: string;
      readonly ownerId?: string;
    },
  ): AsyncResult<DealForecast>;
  health(pipelineId: string): AsyncResult<DealHealth[]>;
}

export interface DealsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Deals>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const KNOWN = new Set([
  "id",
  "tenant_id",
  "number",
  "identifier",
  "name",
  "company_type",
  "company_id",
  "motion",
  "priority",
  "owner_user_id",
  "product",
  "seats",
  "amount",
  "existing_amount",
  "currency",
  "value_period",
  "amount_source",
  "pipeline_id",
  "stage_id",
  "stage_entered_at",
  "outcome",
  "probability",
  "forecast_category",
  "opened_on",
  "expected_close_on",
  "slipped_from",
  "push_count",
  "closed_at",
  "next_step",
  "next_at",
  "next_kind",
  "flags",
  "source",
  "note",
  "lost_reason",
  "locked",
  "rank",
  "archived_at",
  "created_by",
  "created_at",
  "updated_at",
  "list_total",
  "discount_total",
  "subtotal",
  "tax_total",
  "total",
  "contacts",
  "members",
]);

const big = (value: unknown): bigint =>
  typeof value === "string" || typeof value === "number" ? BigInt(value) : 0n;
const num = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;
const date = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string"
    ? temporal().PlainDate.from(value.slice(0, 10))
    : undefined;

function totalsOf(row: Record<string, unknown>, camel = false): DealTotals {
  const key = (snake: string, camelKey: string): unknown =>
    camel ? row[camelKey] : row[snake];
  return {
    listTotal: big(key("list_total", "listTotal")),
    discountTotal: big(key("discount_total", "discountTotal")),
    subtotal: big(key("subtotal", "subtotal")),
    taxTotal: big(key("tax_total", "taxTotal")),
    total: big(key("total", "total")),
  };
}

/** `T` with every optional property allowed to be `undefined`. */
type Loose<T> = { [K in keyof T]: T[K] | undefined };

/** Drops the `undefined` properties, which `exactOptionalPropertyTypes` refuses. */
function compact<T extends object>(value: Loose<T>): T {
  // SAFETY: what is left after dropping undefined keys has the shape of T.
  return Object.fromEntries(
    Object.entries(value).filter(([, item]) => item !== undefined),
  ) as T;
}

function dealOf(value: unknown): Deal {
  const row = recordOf(value, "deal");
  const companyType = optionalText(row["company_type"]);
  const companyId = optionalText(row["company_id"]);
  const forecast = optionalText(row["forecast_category"]);
  return compact<Deal>({
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    number: big(row["number"]),
    identifier: textOf(row["identifier"]),
    name: textOf(row["name"]),
    company:
      companyType === undefined || companyId === undefined
        ? undefined
        : { type: companyType, id: companyId },
    ownerId: optionalText(row["owner_user_id"]),
    motion: optionalText(row["motion"]),
    priority: optionalText(row["priority"]),
    product: optionalText(row["product"]),
    seats: num(row["seats"]),
    amount: big(row["amount"]),
    existingAmount: big(row["existing_amount"]),
    currency: textOf(row["currency"]),
    valuePeriod: enumOrThrow(
      row["value_period"],
      ["one_time", "monthly", "annual"] as const,
      "deal value period",
    ),
    amountSource: enumOrThrow(
      row["amount_source"],
      ["manual", "line_items"] as const,
      "deal amount source",
    ),
    pipelineId: optionalText(row["pipeline_id"]),
    stageId: optionalText(row["stage_id"]),
    stageEnteredAt: optionalInstant(row["stage_entered_at"]),
    outcome: enumOrThrow(row["outcome"], OUTCOMES, "deal outcome"),
    probability: num(row["probability"]),
    forecast:
      forecast === undefined
        ? undefined
        : enumOrThrow(forecast, FORECASTS, "deal forecast"),
    openedOn: date(row["opened_on"]) ?? temporal().PlainDate.from("1970-01-01"),
    closeOn:
      date(row["expected_close_on"]) ?? temporal().PlainDate.from("1970-01-01"),
    slippedFrom: date(row["slipped_from"]),
    pushCount: num(row["push_count"]) ?? 0,
    closedAt: optionalInstant(row["closed_at"]),
    nextStep: optionalText(row["next_step"]),
    nextAt: optionalInstant(row["next_at"]),
    nextKind: optionalText(row["next_kind"]),
    flags: Array.isArray(row["flags"]) ? row["flags"].map(String) : [],
    source: optionalText(row["source"]),
    note: optionalText(row["note"]),
    lostReason: optionalText(row["lost_reason"]),
    locked: row["locked"] === true,
    rank: textOf(row["rank"]),
    totals: totalsOf(row),
    contacts: recordsOf(row["contacts"], "deal contacts").map((contact) =>
      compact<DealContact>({
        type: textOf(contact["type"]),
        id: textOf(contact["id"]),
        role: optionalText(contact["role"]),
        primary: contact["primary"] === true,
      }),
    ),
    members: recordsOf(row["members"], "deal members").map((member) =>
      compact<Deal["members"][number]>({
        userId: textOf(member["userId"]),
        role: optionalText(member["role"]),
      }),
    ),
    fields: Object.fromEntries(
      Object.entries(row).filter(([key]) => !KNOWN.has(key)),
    ),
    archived: row["archived_at"] !== null && row["archived_at"] !== undefined,
    createdAt: requiredInstant(row["created_at"], "createdAt"),
    updatedAt: requiredInstant(row["updated_at"], "updatedAt"),
  });
}

/** A change value as the database reads it: dates as ISO, bigints as text. */
function valueArg(value: unknown): unknown {
  if (typeof value === "bigint") return value.toString();
  if (
    value instanceof temporal().Instant ||
    value instanceof temporal().PlainDate
  ) {
    return value.toString();
  }
  return value;
}

function sums(row: Record<string, unknown>) {
  return {
    won: big(row["won"]),
    commit: big(row["commit"]),
    bestCase: big(row["bestCase"]),
    pipeline: big(row["pipeline"]),
    notCalled: big(row["notCalled"]),
    omit: big(row["omit"]),
    later: big(row["later"]),
  };
}

function forecastOf(value: unknown): DealForecast {
  const row = recordOf(value, "deal_forecast");
  return compact<DealForecast>({
    currency: textOf(row["currency"]),
    ...sums(row),
    target:
      row["target"] === null || row["target"] === undefined
        ? undefined
        : big(row["target"]),
    attainment: num(row["attainment"]),
    gap:
      row["gap"] === null || row["gap"] === undefined
        ? undefined
        : big(row["gap"]),
    owners: recordsOf(row["owners"], "deal_forecast owners").map((owner) =>
      compact<DealForecast["owners"][number]>({
        ownerId: optionalText(owner["ownerId"]),
        ...sums(owner),
      }),
    ),
  });
}

/**
 * The deals block: deals on pipelines, with batched cell edits that reject
 * per change, won and lost through the pipeline's stages, contacts, a team,
 * line items, the forecast call and the review checks.
 */
export function createDeals(options: DealsOptions): Deals {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: Deals = {
    create: (organizationId, input, contacts) =>
      call(
        "create_deal",
        {
          tenant: organizationId,
          attrs: Object.fromEntries(
            Object.entries(input).map(([key, value]) => [key, valueArg(value)]),
          ),
          contacts:
            contacts === undefined
              ? null
              : contacts.map((contact) => ({ ...contact })),
        },
        dealOf,
      ),
    update: (changes) =>
      call(
        "update_deals",
        {
          changes: changes.map((change) => ({
            dealId: change.dealId,
            field: change.field,
            value: valueArg(change.value),
          })),
        },
        (value) => {
          const row = recordOf(value, "update_deals");
          return {
            accepted: recordsOf(row["accepted"], "accepted").map((item) => ({
              dealId: textOf(item["dealId"]),
              field: textOf(item["field"]),
            })),
            rejected: recordsOf(row["rejected"], "rejected").map((item) =>
              compact<DealChangeResult["rejected"][number]>({
                dealId: textOf(item["dealId"]),
                field: textOf(item["field"]),
                hint: optionalText(item["hint"]),
                reason: textOf(item["reason"]),
              }),
            ),
          };
        },
      ),
    win: (dealId, note) =>
      call(
        "close_deal",
        { deal: dealId, outcome: "won", reason: note ?? null },
        dealOf,
      ),
    lose: (dealId, reason) =>
      call(
        "close_deal",
        { deal: dealId, outcome: "lost", reason: reason ?? null },
        dealOf,
      ),
    reopen: (dealId, stageId) =>
      call("reopen_deal", { deal: dealId, stage: stageId ?? null }, dealOf),
    setContacts: (dealId, contacts) =>
      call(
        "set_deal_contacts",
        { deal: dealId, contacts: contacts.map((contact) => ({ ...contact })) },
        (value) => num(value) ?? 0,
      ),
    setMembers: (dealId, members) =>
      call(
        "set_deal_members",
        { deal: dealId, members: members.map((member) => ({ ...member })) },
        (value) => num(value) ?? 0,
      ),
    setLines: (dealId, lines) =>
      call(
        "set_deal_lines",
        {
          parent: dealId,
          lines: lines.map((line) => ({
            ...line,
            unitAmount: line.unitAmount.toString(),
          })),
        },
        (value) => totalsOf(recordOf(value, "set_deal_lines"), true),
      ),
    archive: (dealId, archived = true) =>
      call(
        "archive_deal",
        { deal: dealId, archived },
        (value) => value === true,
      ),
    remove: (dealId) =>
      call("delete_deal", { deal: dealId }, (value) => value === true),
    forecast: (organizationId, period) =>
      call(
        "deal_forecast",
        {
          tenant: organizationId,
          pipeline: period.pipelineId ?? null,
          since: period.since.toString(),
          until: period.until.toString(),
          currency: period.currency,
          target: period.target === undefined ? null : period.target.toString(),
          owner: period.ownerId ?? null,
        },
        forecastOf,
      ),
    health: (pipelineId) =>
      call("deal_health", { pipeline: pipelineId }, (value) =>
        recordsOf(value, "deal_health").map((row) => ({
          dealId: textOf(row["dealId"]),
          identifier: textOf(row["identifier"]),
          name: textOf(row["name"]),
          daysInStage: num(row["daysInStage"]) ?? 0,
          rotting: row["rotting"] === true,
          slipped: row["slipped"] === true,
          noNextStep: row["noNextStep"] === true,
          overdue: row["overdue"] === true,
        })),
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "deals",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

/**
 * The `config.subjects` entry for deals, so comments, tags, files, rank and
 * search attach to them. The board moves a deal by its stage id.
 */
export function dealsSubjects(
  options: { readonly schema?: string; readonly url?: string } = {},
): { readonly deal: SubjectConfig } {
  return {
    deal: {
      table: `${options.schema ?? DEFAULT_BLOCK_SCHEMA}.deals`,
      idType: "uuid",
      tenant: "tenant_id",
      title: "name",
      deletedAt: "archived_at",
      permissions: { read: "deals.read", write: "deals.write" },
      rank: { column: "rank", group: "stage_id" },
      search: { title: "name", body: ["identifier", "note"] },
      ...(options.url === undefined ? {} : { url: options.url }),
    },
  };
}
