import type { SubjectConfig } from "../../config/types/subjects.ts";
import type { ExtraColumn, ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  type RegisteredSubject,
  registeredSubjects,
} from "../subject-registry.ts";

/** The fixed outcomes every stage category maps to. Reports read these, never stage names. */
const PIPELINE_OUTCOMES = ["open", "success", "failure"] as const;

type PipelineOutcome = (typeof PIPELINE_OUTCOMES)[number];

const NAME = /^[a-z][a-z0-9_]{0,62}$/;
const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/;

/** A default stage a subject's first pipeline starts with. */
interface StageTemplate {
  readonly key: string;
  readonly name: string;
  readonly category: string;
  readonly probability?: number;
}

/** One `options.subjects` entry, checked against `config.subjects`. */
export interface PipelineBinding {
  readonly type: string;
  readonly subject: RegisteredSubject;
  readonly stage: string;
  readonly pipeline: string;
  readonly enteredAt?: string;
  readonly amount?: string;
  readonly currency?: string;
  readonly probability?: string;
  readonly owner?: string;
  readonly scope?: string;
  readonly categories: Readonly<Record<string, PipelineOutcome>>;
  readonly status?: {
    readonly column: string;
    readonly values: Readonly<Record<string, string>>;
  };
  readonly stages: readonly StageTemplate[];
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function columnOf(
  where: string,
  value: unknown,
  fallback?: string,
): string | undefined {
  if (value === undefined) {
    return fallback;
  }

  if (typeof value !== "string" || !COLUMN.test(value)) {
    throw new TypeError(`${where} must be a column name`);
  }

  return value;
}

function categoriesOf(
  where: string,
  value: unknown,
): Record<string, PipelineOutcome> {
  if (!isRecord(value) || Object.keys(value).length === 0) {
    throw new TypeError(
      `${where}.categories must map each category to open, success or failure`,
    );
  }

  const out: Record<string, PipelineOutcome> = {};

  for (const [name, outcome] of Object.entries(value)) {
    if (!NAME.test(name)) {
      throw new TypeError(`${where}.categories.${name} has an invalid name`);
    }

    const known = PIPELINE_OUTCOMES.find((item) => item === outcome);

    if (known === undefined) {
      throw new TypeError(
        `${where}.categories.${name} must be open, success or failure`,
      );
    }

    out[name] = known;
  }

  if (!Object.values(out).includes("open")) {
    throw new TypeError(`${where}.categories needs an open category`);
  }

  return out;
}

function stagesOf(
  where: string,
  value: unknown,
  categories: Readonly<Record<string, PipelineOutcome>>,
): readonly StageTemplate[] {
  if (value === undefined) {
    return Object.keys(categories).map((category) => ({
      key: category,
      name: category.charAt(0).toUpperCase() + category.slice(1),
      category,
    }));
  }

  if (!Array.isArray(value) || value.length === 0) {
    throw new TypeError(`${where}.stages must be a non-empty list`);
  }

  const keys = new Set<string>();

  const stages = value.map((item: unknown, index): StageTemplate => {
    const at = `${where}.stages[${String(index)}]`;

    if (!isRecord(item)) {
      throw new TypeError(`${at} must be an object`);
    }

    const { key, name, category, probability } = item;

    if (typeof key !== "string" || !NAME.test(key) || keys.has(key)) {
      throw new TypeError(`${at}.key must be a distinct lowercase name`);
    }

    keys.add(key);

    if (typeof name !== "string" || name.length === 0) {
      throw new TypeError(`${at}.name is required`);
    }

    if (typeof category !== "string" || !(category in categories)) {
      throw new TypeError(`${at}.category must be one of the categories`);
    }

    if (
      probability !== undefined &&
      (typeof probability !== "number" ||
        !Number.isInteger(probability) ||
        probability < 0 ||
        probability > 100)
    ) {
      throw new TypeError(`${at}.probability must be an integer 0 to 100`);
    }

    return {
      key,
      name,
      category,
      ...(typeof probability === "number" && { probability }),
    };
  });

  if (!stages.some((stage) => categories[stage.category] === "open")) {
    throw new TypeError(`${where}.stages needs an open stage`);
  }

  return stages;
}

function statusOf(
  where: string,
  value: unknown,
  categories: Readonly<Record<string, PipelineOutcome>>,
): PipelineBinding["status"] {
  if (value === undefined) {
    return undefined;
  }

  if (!isRecord(value) || !isRecord(value["values"])) {
    throw new TypeError(`${where}.status needs column and values`);
  }

  const column = columnOf(`${where}.status.column`, value["column"]);

  if (column === undefined) {
    throw new TypeError(`${where}.status.column is required`);
  }

  const values: Record<string, string> = {};

  for (const [category, status] of Object.entries(value["values"])) {
    if (!(category in categories)) {
      throw new TypeError(`${where}.status.values.${category} is no category`);
    }

    if (typeof status !== "string" || status.length === 0) {
      throw new TypeError(`${where}.status.values.${category} must be text`);
    }

    values[category] = status;
  }

  return { column, values };
}

/** `options.subjects`, checked: one binding per subject type that runs on pipelines. */
/**
 * The binding a record block brings when it is installed: the subject type,
 * its module and table, and the binding entry. An app's own entry for the
 * type in options.subjects is merged over it.
 */
interface BuiltInBinding {
  readonly module: string;
  readonly table: string;
  readonly type: string;
  readonly entry: Readonly<Record<string, unknown>>;
}

/** The record blocks that run on pipelines. */
const BUILT_IN_BINDINGS: readonly BuiltInBinding[] = [
  {
    module: "deals",
    table: "deals",
    type: "deal",
    entry: {
      enteredAt: "stage_entered_at",
      amount: "amount",
      currency: "currency",
      probability: "probability",
      owner: "owner_user_id",
      categories: { open: "open", won: "success", lost: "failure" },
      status: {
        column: "outcome",
        values: { open: "open", won: "won", lost: "lost" },
      },
      stages: [
        {
          key: "qualified",
          name: "Qualified",
          category: "open",
          probability: 20,
        },
        {
          key: "discovery",
          name: "Discovery",
          category: "open",
          probability: 35,
        },
        {
          key: "proposal",
          name: "Proposal",
          category: "open",
          probability: 55,
        },
        {
          key: "negotiation",
          name: "Negotiation",
          category: "open",
          probability: 75,
        },
        {
          key: "closed_won",
          name: "Closed won",
          category: "won",
          probability: 100,
        },
        {
          key: "closed_lost",
          name: "Closed lost",
          category: "lost",
          probability: 0,
        },
      ],
    },
  },
  {
    module: "work-items",
    table: "items",
    type: "work_item",
    entry: {
      enteredAt: "stage_entered_at",
      scope: "team_id",
      categories: {
        triage: "open",
        backlog: "open",
        unstarted: "open",
        started: "open",
        completed: "success",
        canceled: "failure",
      },
      status: {
        column: "state",
        values: {
          triage: "triage",
          backlog: "backlog",
          unstarted: "unstarted",
          started: "started",
          completed: "completed",
          canceled: "canceled",
        },
      },
      stages: [
        { key: "triage", name: "Triage", category: "triage" },
        { key: "backlog", name: "Backlog", category: "backlog" },
        { key: "todo", name: "Todo", category: "unstarted" },
        { key: "in_progress", name: "In progress", category: "started" },
        { key: "in_review", name: "In review", category: "started" },
        { key: "done", name: "Done", category: "completed" },
        { key: "canceled", name: "Canceled", category: "canceled" },
      ],
    },
  },
  {
    module: "hiring",
    table: "applications",
    type: "application",
    entry: {
      enteredAt: "stage_entered_at",
      owner: "owner_user_id",
      scope: "job_id",
      categories: {
        active: "open",
        hired: "success",
        rejected: "failure",
        withdrawn: "failure",
      },
      status: {
        column: "state",
        values: {
          active: "active",
          hired: "hired",
          rejected: "rejected",
          withdrawn: "withdrawn",
        },
      },
      stages: [
        { key: "applied", name: "Applied", category: "active" },
        { key: "screening", name: "Screening", category: "active" },
        { key: "interview", name: "Interview", category: "active" },
        { key: "offer", name: "Offer", category: "active" },
        { key: "hired", name: "Hired", category: "hired" },
        { key: "rejected", name: "Rejected", category: "rejected" },
        { key: "withdrawn", name: "Withdrawn", category: "withdrawn" },
      ],
    },
  },
];

export function pipelineBindings(
  ctx: ModuleContext,
): readonly PipelineBinding[] {
  const configured = ctx.option("subjects") ?? {};

  if (!isRecord(configured)) {
    throw new TypeError("blocks.pipelines.options.subjects must be an object");
  }

  const raw: Record<string, unknown> = {};
  const builtInSubjects: Record<string, SubjectConfig> = {};

  for (const builtIn of BUILT_IN_BINDINGS) {
    if (!ctx.installed(builtIn.module)) {
      continue;
    }

    const own = configured[builtIn.type];
    raw[builtIn.type] = { ...builtIn.entry, ...(isRecord(own) ? own : {}) };
    const { schema, name } = ctx.of(builtIn.module).tableName(builtIn.table);
    builtInSubjects[builtIn.type] = {
      table: `${schema}.${name}`,
      idType: "uuid",
      tenant: "tenant_id",
    };
  }

  for (const [type, entry] of Object.entries(configured)) {
    if (!(type in raw)) {
      raw[type] = entry;
    }
  }

  const registry = registeredSubjects({ ...builtInSubjects, ...ctx.subjects });

  return Object.entries(raw).map(([type, entry]) => {
    const where = `blocks.pipelines.options.subjects.${type}`;
    const subject = registry.find((item) => item.type === type);

    if (subject === undefined) {
      throw new TypeError(
        `${where}: register "${type}" in config.subjects first`,
      );
    }

    if (subject.tenant === undefined) {
      throw new TypeError(
        `${where}: config.subjects.${type} needs a tenant column`,
      );
    }

    if (!isRecord(entry)) {
      throw new TypeError(`${where} must be an object`);
    }

    const categories = categoriesOf(where, entry["categories"]);

    const optional = (key: string): string | undefined =>
      columnOf(`${where}.${key}`, entry[key]);

    const amount = optional("amount");
    const currency = optional("currency");

    if ((amount === undefined) !== (currency === undefined)) {
      throw new TypeError(`${where}: amount and currency go together`);
    }

    const status = statusOf(where, entry["status"], categories);
    const enteredAt = optional("enteredAt");
    const probability = optional("probability");
    const owner = optional("owner");
    const scope = optional("scope");

    return {
      type,
      subject,
      stage:
        columnOf(`${where}.stage`, entry["stage"], "stage_id") ?? "stage_id",
      pipeline:
        columnOf(`${where}.pipeline`, entry["pipeline"], "pipeline_id") ??
        "pipeline_id",
      categories,
      stages: stagesOf(where, entry["stages"], categories),
      ...(enteredAt !== undefined && { enteredAt }),
      ...(amount !== undefined && { amount }),
      ...(currency !== undefined && { currency }),
      ...(probability !== undefined && { probability }),
      ...(owner !== undefined && { owner }),
      ...(scope !== undefined && { scope }),
      ...(status !== undefined && { status }),
    };
  });
}

export interface Names {
  readonly fn: (name: string) => string;
  /** `options.extraColumns` of the pipelines table. */
  readonly extras: readonly ExtraColumn[];
  readonly read: string;
  readonly manage: string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
}

/** `case subject_type when ... then <branch> ... else <otherwise> end case;` over the bindings. */
export function byType(
  selector: string,
  bindings: readonly PipelineBinding[],
  branch: (binding: PipelineBinding) => string,
  otherwise: string,
): string {
  if (bindings.length === 0) {
    return otherwise;
  }

  return `case ${selector}
${bindings.map((binding) => `    when ${sqlString(binding.type)} then\n${branch(binding)}`).join("\n")}
    else
      ${otherwise}
  end case;`;
}

/** The category's outcome for one subject type, as a SQL `case` over `category`. */
export function outcomeCase(
  binding: PipelineBinding,
  category: string,
): string {
  return `case ${category}
${Object.entries(binding.categories)
  .map(
    ([name, outcome]) =>
      `      when ${sqlString(name)} then ${sqlString(outcome)}`,
  )
  .join("\n")}
    end`;
}
