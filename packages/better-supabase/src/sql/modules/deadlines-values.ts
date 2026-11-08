// The deadlines block's fixed values and the types of a rule set version and
// its results. `deadlines-evaluate.ts` and `deadlines-validate.ts` build on
// them, and none of the three imports anything else, so the client entry runs
// the same evaluation and validation as the SQL functions (ADR 0242).

/** The states of a version of a rule set. */
export const RULE_VERSION_STATUSES = ["draft", "approved"] as const;

/** What one group of a rule set version yields for a subject. */
export const DEADLINE_RESULTS = [
  "due",
  "unknown",
  "pending",
  "undated",
  "not_covered",
  "not_applicable",
  "not_required",
  "barred",
] as const;

export type DeadlineResult = (typeof DEADLINE_RESULTS)[number];

/** Where a deadline stands: pending until an action satisfies it. */
export const DEADLINE_STATES = ["pending", "satisfied"] as const;

export const OFFSET_UNITS = ["days", "business_days", "months"] as const;

export type OffsetUnit = (typeof OFFSET_UNITS)[number];

/** How a date that lands on a non-business day moves after the roll. */
export const DEADLINE_ADJUSTMENTS = [
  "none",
  "next_business_day",
  "previous_business_day",
] as const;

export type DeadlineAdjustment = (typeof DEADLINE_ADJUSTMENTS)[number];

/** The largest count a rule may carry, in its unit. */
export const OFFSET_LIMIT = 3650;

/** The approval state of a rule, an exception or a counting block. */
export const PART_STATUSES = ["approved", "draft", "review_required"] as const;

export type PartStatus = (typeof PART_STATUSES)[number];

/** What a settled exception decides; `review_required` never decides. */
export const EXCEPTION_RESULTS = [
  "barred",
  "not_applicable",
  "not_required",
  "review_required",
] as const;

/** The days a counting block can roll a last day past. */
export const ROLL_DAYS = ["saturday", "sunday", "holiday"] as const;

export type RollDay = (typeof ROLL_DAYS)[number];

export const WEEKDAYS = [
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
  "sunday",
] as const;

export type Weekday = (typeof WEEKDAYS)[number];

/** The listed day an observed shift reads. */
export const OBSERVED_FALLS_ON = [
  "saturday",
  "sunday",
  "other_than_sunday",
] as const;

/** Where an observed shift moves a holiday, strictly before or after it. */
export const OBSERVED_MOVES = [
  "preceding_friday",
  "following_monday",
  "preceding_sunday",
  "following_sunday",
] as const;

/** The largest `meta` object, in bytes of its jsonb text. */
export const META_LIMIT = 32_768;

/** The fact a monthly count reads its first furnishing month from. */
export const FIRST_FURNISHING_FACT = "first_furnishing_date";

/** The fact that ends a monthly count's months. */
export const LAST_FURNISHING_FACT = "last_furnishing_date";

/** A name of a fact, a group or an exception. */
export const DEADLINE_NAME: RegExp = /^[a-z][a-z0-9_]{0,62}$/u;

/** A rule key, long enough for `<group>__<cell>`. */
export const RULE_KEY: RegExp = /^[a-z][a-z0-9_]{0,127}$/u;

/** The longest exception note. */
export const NOTE_LIMIT = 2000;

export const ISO_DATE: RegExp = /^(\d{4})-(\d{2})-(\d{2})$/u;

/** Where a rule comes from. */
export interface DeadlineCitation {
  /** A statute or regulation reference, such as `Section 12(3)`. */
  readonly reference: string;
  readonly url?: string;
  /** The quoted text the rule follows. */
  readonly text?: string;
}

/**
 * One condition value: equals for a string or a boolean, any of for a list of
 * codes, and the existence of the fact for `present` or `absent`.
 */
export type ConditionValue = string | boolean | readonly string[];

/** An AND of entries, keyed by fact name. */
export type Condition = Readonly<Record<string, ConditionValue>>;

/** A date regime: the fact's date is on or after `from` and before `before`. */
export interface DateRegime {
  readonly from?: string;
  readonly before?: string;
}

/**
 * What selects a rule: a list of codes per fact, `present` or `absent`, and at
 * most one date regime.
 */
export type Applies = Readonly<Record<string, ConditionValue | DateRegime>>;

/** One count: `n` units from a fact's date, or before it. */
export interface DeadlineCount {
  /** Required unless the count is `before` a fact without one ("on or before"). */
  readonly n?: number;
  /** Required with `n`. */
  readonly unit?: OffsetUnit;
  /** Exactly one of `from` and `before` names the fact the count reads. */
  readonly from?: string;
  readonly before?: string;
  /** With `months`: the day of the target month, clamped to its last day. */
  readonly day_of_month?: number;
  /** One deadline per furnishing month, each counted from the first of it. */
  readonly each?: "furnishing_month";
}

/** A rule's deadline: none, one count, or a combinator of two or more. */
export type DeadlineSpec =
  | "none"
  | DeadlineCount
  | { readonly first_of: readonly DeadlineCount[] }
  | { readonly earlier_of: readonly DeadlineCount[] }
  | { readonly later_of: readonly DeadlineCount[] };

/** An exception of a rule: what the subject's facts change about the duty. */
export interface DeadlineException {
  readonly name: string;
  readonly when: Condition;
  /** A missing `unless` never holds. */
  readonly unless?: Condition;
  readonly result: (typeof EXCEPTION_RESULTS)[number];
  /** Where the remedy moved when barred, such as `claim_against_bond`. */
  readonly remedy?: string;
  readonly citation: DeadlineCitation;
  readonly note?: string;
  /** `approved` by default; `review_required` never decides. */
  readonly status?: PartStatus;
}

/** One rule: when it applies, its exceptions and the deadline it counts. */
export interface DeadlineRule {
  /** The name of the rule inside its version. */
  readonly key: string;
  /** The group it belongs to; the first rule of a group that applies wins. */
  readonly group: string;
  readonly title?: string;
  /** Absent: the rule applies to every subject. */
  readonly applies?: Applies;
  /** `false`: the duty does not exist for the subjects it selects. */
  readonly required?: boolean;
  /** Absent means `none`: a duty without a date. */
  readonly deadline?: DeadlineSpec;
  readonly exceptions?: readonly DeadlineException[];
  /** Moves a result off a non-business day after the counting roll. */
  readonly adjust?: DeadlineAdjustment;
  /** `approved` by default; any other status is carried for review only. */
  readonly status?: PartStatus;
  readonly citation: DeadlineCitation;
  /** Opaque data the block keeps and never reads. */
  readonly meta?: Readonly<Record<string, unknown>>;
}

/** A group of rules: one result per subject (one per month for a periodic rule). */
export interface DeadlineGroup {
  readonly key: string;
  readonly title?: string;
  readonly citation: DeadlineCitation;
  /** Groups whose `barred` result bars this one too. */
  readonly requires?: readonly string[];
  readonly meta?: Readonly<Record<string, unknown>>;
}

/** One holiday of a counting block. */
export interface DeadlineHoliday {
  readonly name: string;
  readonly date:
    | { readonly month: number; readonly day: number }
    | {
        readonly month: number;
        readonly weekday: Weekday;
        readonly nth: 1 | 2 | 3 | 4 | 5 | "last";
      };
  readonly citation: DeadlineCitation;
  readonly observed?: readonly {
    readonly falls_on: (typeof OBSERVED_FALLS_ON)[number];
    readonly observe: (typeof OBSERVED_MOVES)[number];
    /** The listed date stops being a holiday. */
    readonly replaces?: boolean;
    readonly citation: DeadlineCitation;
  }[];
}

/** How a version counts: the days a last day rolls past, and its holidays. */
export interface DeadlineCounting {
  readonly roll_to: "next_business_day";
  readonly roll_when: readonly RollDay[];
  readonly holidays?: readonly DeadlineHoliday[];
  readonly citation?: DeadlineCitation;
  /** Only an approved block rolls a date. */
  readonly status?: PartStatus;
}

/** What `save_rule_version` takes and a version row holds. */
export interface RuleVersionContent {
  readonly rules: readonly DeadlineRule[];
  readonly groups: readonly DeadlineGroup[];
  readonly counting?: DeadlineCounting | null;
  readonly meta?: Readonly<Record<string, unknown>> | null;
}

/** Why a result needs a person to look at it; it never changes the result. */
export type DeadlineReview =
  | {
      readonly kind: "regime";
      readonly fact: string;
      readonly from: string | null;
    }
  | {
      readonly kind: "exception";
      readonly name: string;
      readonly citation: DeadlineCitation;
      readonly note?: string;
    }
  | { readonly kind: "rule"; readonly status: PartStatus }
  | { readonly kind: "counting"; readonly status: PartStatus };

/** What a dated result rests on. */
export interface DeadlineBasis {
  /** The fact and date the taken count read; null for earlier_of and later_of. */
  readonly anchor: { readonly fact: string; readonly date: string } | null;
  /** The `from` facts counted as not having happened. */
  readonly without: readonly string[];
}

/** The exception that decided a result. */
export interface DeadlineExceptionResult {
  readonly name: string;
  readonly citation: DeadlineCitation;
  readonly remedy?: string;
  readonly note?: string;
}

/** One result of a group for a subject. */
export interface DeadlineGroupResult {
  readonly group: string;
  readonly ruleKey: string | null;
  /** `YYYY-MM` for a monthly count's month. */
  readonly period: string | null;
  readonly result: DeadlineResult;
  readonly dueOn: string | null;
  /** A date or result that a missing answer could still change. */
  readonly provisional: boolean;
  /** The facts still asked, sorted. */
  readonly missing: readonly string[];
  readonly exception: DeadlineExceptionResult | null;
  readonly review: readonly DeadlineReview[];
  readonly basis: DeadlineBasis | null;
  /** The selected rule's deadline as authored. */
  readonly deadline: DeadlineSpec | null;
  /** The rule's citation, else the group's. */
  readonly citation: DeadlineCitation;
}

/** Facts: a missing key is unknown, `null` does not exist or has not happened. */
export type DeadlineFacts = Readonly<Record<string, unknown>>;

type Json = Readonly<Record<string, unknown>>;

/** A plain object, not an array or null. */
export function isRecord(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Whether an object has its own key. */
export function has(value: Json, key: string): boolean {
  return Object.hasOwn(value, key);
}
