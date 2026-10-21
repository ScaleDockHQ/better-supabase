import type { Money } from "../../commerce/money.ts";
import type { SubjectConfig } from "../../config/types/subjects.ts";
import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { isCurrency, isMoney } from "../../commerce/money.ts";
import { blockFields } from "../../core/block-fields.ts";
import { DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  amountsError,
  amountText,
  currencyMismatch,
  moneyOf,
  optionalAmountText,
  optionalMoneyOf,
  unknownCurrency,
} from "../money-codec.ts";
import { lineArg, totalsOf } from "../sales-lines.ts";
import { plainDate } from "../sales-shared.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
  bigintOf,
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

/** A deal. `F` types the extra columns the `fields` schema describes. */
export interface Deal<F extends object = Record<never, never>> {
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
  readonly amount: Money;
  /** The revenue the account already brings, for an expansion. */
  readonly existingAmount: Money;
  /** The deal's currency, which every amount on it shares. */
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
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: Readonly<Record<string, unknown>> & F;
  readonly archived: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** Line totals in the deal's currency: list, discount, subtotal, tax and total. */
export interface DealTotals {
  readonly listTotal: Money;
  readonly discountTotal: Money;
  readonly subtotal: Money;
  readonly taxTotal: Money;
  readonly total: Money;
}

export interface DealInput<F extends object = Record<never, never>> {
  readonly name: string;
  readonly closeOn: Temporal.PlainDate;
  readonly amount?: Money;
  /** Defaults to the amounts' currency, then `EUR`. */
  readonly currency?: string;
  readonly company?: DealParty;
  readonly ownerId?: string;
  readonly motion?: string;
  readonly priority?: string;
  readonly product?: string;
  readonly seats?: number;
  readonly existingAmount?: Money;
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
  /** Values for the extra columns, by column name. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
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

/** One cell edit: a field above, or an extra column by name. `null` clears it. */
export interface DealChange {
  readonly dealId: string;
  readonly field: DealField | (string & {});
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

/** A line of a deal, in the deal's currency. */
export interface DealLineInput {
  readonly description: string;
  readonly quantity?: number;
  readonly unitAmount: Money;
  readonly discountBps?: number;
  readonly taxRateBps?: number;
  readonly taxCode?: string;
  readonly product?: DealParty;
}

/** The forecast call for one currency. */
export interface DealForecast {
  readonly currency: string;
  readonly won: Money;
  readonly commit: Money;
  readonly bestCase: Money;
  readonly pipeline: Money;
  readonly notCalled: Money;
  readonly omit: Money;
  /** Open deals that close after the period. */
  readonly later: Money;
  readonly target?: Money;
  /** Won plus commit over the target. */
  readonly attainment?: number;
  readonly gap?: Money;
  readonly owners: readonly (Omit<
    DealForecast,
    "owners" | "currency" | "target" | "attainment" | "gap"
  > & { readonly ownerId?: string })[];
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

/** `F` types the deals' extra columns, from the `fields` schema. */
export interface Deals<F extends object = Record<never, never>> {
  create(
    organizationId: string,
    input: DealInput<F>,
    contacts?: readonly DealContact[],
  ): AsyncResult<Deal<F>>;
  /** Applies cell edits; a refused change leaves the others applied. */
  update(changes: readonly DealChange[]): AsyncResult<DealChangeResult>;
  /** Moves the deal to its pipeline's won stage. `note` is the closing note. */
  win(dealId: string, note?: string): AsyncResult<Deal<F>>;
  /** Moves the deal to its pipeline's lost stage. */
  lose(dealId: string, reason?: string): AsyncResult<Deal<F>>;
  /** Opens a closed deal again, in `stageId` or the first open stage. */
  reopen(dealId: string, stageId?: string): AsyncResult<Deal<F>>;
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
      /** In `currency`. */
      readonly target?: Money;
      readonly pipelineId?: string;
      readonly ownerId?: string;
    },
  ): AsyncResult<DealForecast>;
  health(pipelineId: string): AsyncResult<DealHealth[]>;
}

export interface DealsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  /**
   * A Standard Schema for the deals' extra columns
   * (`blocks.deals.options.extraColumns`), keyed by column name. It types and
   * parses `fields` on reads and validates them on writes.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Deals<FieldsOf<S>>>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** The fields `update` writes, by name: any other field is an extra column. */
const BUILT_IN: ReadonlySet<string> = new Set<DealField>([
  "name",
  "motion",
  "priority",
  "ownerId",
  "product",
  "seats",
  "amount",
  "existingAmount",
  "currency",
  "valuePeriod",
  "amountSource",
  "stageId",
  "probability",
  "forecast",
  "closeOn",
  "nextStep",
  "nextAt",
  "nextKind",
  "flags",
  "source",
  "note",
  "lostReason",
  "company",
]);

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

const num = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

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
    number: bigintOf(row["number"], "deal number"),
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
    amount: moneyOf(row["amount"], row["currency"], "deal amount"),
    existingAmount: moneyOf(
      row["existing_amount"],
      row["currency"],
      "deal existingAmount",
    ),
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
    openedOn:
      plainDate(row["opened_on"]) ?? temporal().PlainDate.from("1970-01-01"),
    closeOn:
      plainDate(row["expected_close_on"]) ??
      temporal().PlainDate.from("1970-01-01"),
    slippedFrom: plainDate(row["slipped_from"]),
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
    totals: totalsOf(row, false),
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

/**
 * A value as the database reads it: dates as ISO, bigints and the minor units
 * of a `Money` as text.
 */
function valueArg(value: unknown): unknown {
  if (typeof value === "bigint") {
    return value.toString();
  }

  if (isMoney(value)) {
    return amountText(value);
  }

  if (
    value instanceof temporal().Instant ||
    value instanceof temporal().PlainDate
  ) {
    return value.toString();
  }

  return value;
}

function sums(row: Readonly<Record<string, unknown>>, currency: string) {
  const at = (key: string): Money =>
    moneyOf(row[key], currency, `deal_forecast ${key}`);

  return {
    won: at("won"),
    commit: at("commit"),
    bestCase: at("bestCase"),
    pipeline: at("pipeline"),
    notCalled: at("notCalled"),
    omit: at("omit"),
    later: at("later"),
  };
}

function forecastOf(value: unknown): DealForecast {
  const row = recordOf(value, "deal_forecast");
  const currency = textOf(row["currency"]);

  return compact<DealForecast>({
    currency,
    ...sums(row, currency),
    target: optionalMoneyOf(row["target"], currency, "deal_forecast target"),
    attainment: num(row["attainment"]),
    gap: optionalMoneyOf(row["gap"], currency, "deal_forecast gap"),
    owners: recordsOf(row["owners"], "deal_forecast owners").map((owner) =>
      compact<DealForecast["owners"][number]>({
        ownerId: optionalText(owner["ownerId"]),
        ...sums(owner, currency),
      }),
    ),
  });
}

/**
 * The deals block: deals on pipelines, with batched cell edits that reject per
 * change, won and lost through the pipeline's stages, contacts, a team, line
 * items, the forecast call and the review checks.
 */
export function createDeals<S extends StandardSchemaV1 | undefined = undefined>(
  options: DealsOptions<S>,
): Deals<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "deal fields");

  const parsed = (deal: Deal): AsyncResult<Deal<F>> =>
    AsyncResult.from(() => fields.read(deal.fields)).map((value) => ({
      ...deal,
      fields: value,
    }));

  const client: Deals<F> = {
    create: (organizationId, input, contacts) => {
      const { fields: extra, ...rest } = input;

      const invalid = amountsError(input.currency, [
        input.amount,
        input.existingAmount,
      ]);

      if (invalid !== undefined) {
        return AsyncResult.err(invalid);
      }

      const currency =
        input.currency ??
        input.amount?.currency ??
        input.existingAmount?.currency;

      return AsyncResult.from(() => fields.write({ ...extra }))
        .andThen((valid) =>
          call(
            "create_deal",
            {
              tenant: organizationId,
              attrs: Object.fromEntries(
                Object.entries({
                  ...rest,
                  ...(currency === undefined ? {} : { currency }),
                  ...valid,
                }).map(([key, value]) => [key, valueArg(value)]),
              ),
              contacts:
                contacts === undefined
                  ? null
                  : contacts.map((contact) => ({ ...contact })),
            },
            dealOf,
          ),
        )
        .andThen(parsed);
    },
    update: (changes) =>
      AsyncResult.from(async () => {
        for (const change of changes) {
          if (
            change.field === "currency" &&
            typeof change.value === "string" &&
            !isCurrency(change.value)
          ) {
            return err(unknownCurrency(change.value));
          }

          if (BUILT_IN.has(change.field)) {
            continue;
          }

          const valid = await fields.write({ [change.field]: change.value });

          if (!valid.ok) {
            return valid;
          }
        }

        return ok(changes);
      }).andThen((checked) =>
        call(
          "update_deals",
          {
            changes: checked.map((change) => ({
              dealId: change.dealId,
              field: change.field,
              value: isMoney(change.value)
                ? {
                    amount: amountText(change.value),
                    currency: change.value.currency,
                  }
                : valueArg(change.value),
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
      ),
    win: (dealId, note) =>
      call(
        "close_deal",
        { deal: dealId, outcome: "won", reason: note ?? null },
        dealOf,
      ).andThen(parsed),
    lose: (dealId, reason) =>
      call(
        "close_deal",
        { deal: dealId, outcome: "lost", reason: reason ?? null },
        dealOf,
      ).andThen(parsed),
    reopen: (dealId, stageId) =>
      call(
        "reopen_deal",
        { deal: dealId, stage: stageId ?? null },
        dealOf,
      ).andThen(parsed),
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
    setLines: (dealId, lines) => {
      const invalid = currencyMismatch(
        undefined,
        lines.map((line) => line.unitAmount),
      );

      return invalid === undefined
        ? call(
            "set_deal_lines",
            { parent: dealId, lines: lines.map(lineArg) },
            (value) => totalsOf(recordOf(value, "set_deal_lines"), true),
          )
        : AsyncResult.err(invalid);
    },
    archive: (dealId, archived = true) =>
      call(
        "archive_deal",
        { deal: dealId, archived },
        (value) => value === true,
      ),
    remove: (dealId) =>
      call("delete_deal", { deal: dealId }, (value) => value === true),
    forecast: (organizationId, period) => {
      const invalid = amountsError(period.currency, [period.target]);

      return invalid === undefined
        ? call(
            "deal_forecast",
            {
              tenant: organizationId,
              pipeline: period.pipelineId ?? null,
              since: period.since.toString(),
              until: period.until.toString(),
              currency: period.currency,
              target: optionalAmountText(period.target),
              owner: period.ownerId ?? null,
            },
            forecastOf,
          )
        : AsyncResult.err(invalid);
    },
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
