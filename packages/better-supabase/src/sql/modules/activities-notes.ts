import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The note categories `options.noteCategories` falls back to. */
const NOTE_CATEGORIES = [
  "general",
  "care",
  "medical",
  "behavior",
  "family",
  "incident",
] as const;

/** The engagement types `options.lockTypes` falls back to. */
const LOCK_TYPES = ["note", "report"] as const;

/** Who reads an engagement besides the tenant's readers. */
const AUDIENCES = ["team", "subject", "restricted"] as const;

const NAME = /^[a-z][a-z0-9_-]{0,62}$/;

/** The most hours `options.lockAfterHours` takes: one year. */
const MAX_LOCK_HOURS = 8760;

/** The progress note columns of the engagements table (Recipe B, optional). */
export const NOTE_COLUMNS = {
  audience: "audience",
  restrictedRoles: "restricted_roles",
  category: "category",
  lockedAt: "locked_at",
  amends: "amends_id",
  goal: "goal_id",
  markedErrorAt: "marked_error_at",
  markedErrorBy: "marked_error_by",
  markedErrorReason: "marked_error_reason",
} as const;

export const NOTE_OPTIONS = [
  "noteCategories",
  "lockAfterHours",
  "lockTypes",
] as const;

function names(
  ctx: BlockSqlContext,
  option: string,
  fallback: readonly string[],
): readonly string[] {
  const list = ctx.list(option, fallback);

  if (list.some((item) => !NAME.test(item))) {
    throw new TypeError(
      `blocks.activities.options.${option} must be a list of lowercase names`,
    );
  }

  return list;
}

const textArray = (list: readonly string[]): string =>
  `${sqlString(`{${list.join(",")}}`)}::text[]`;

/** The parts of the engagement SQL that progress notes change. */
export interface NoteRules {
  /** Whether the table has the column (`NOTE_COLUMNS`). */
  readonly on: (column: keyof typeof NOTE_COLUMNS) => boolean;
  /** Whether guests read `subject` engagements through their grants. */
  readonly guests: boolean;
  /**
   * The extra condition a member's read of row `p` passes: a `restricted`
   * engagement needs `activities.read_restricted`, one of its roles on a linked
   * record's team, or to be its author or owner. `true` without the audience
   * column.
   */
  readonly memberRead: (p: string) => string;
  /** A guest's read of row `p`, `false` without guests. */
  readonly guestRead: (p: string) => string;
  /** Row `p` is locked now: past `locked_at` or marked in error. */
  readonly locked: (p: string) => string;
  /** The `locked_at` a row of type `type` created at `from` gets. */
  readonly lockAt: (type: string, from: string) => string;
  /** Checks `<fn>.attrs` (audience, restrictedRoles, category) in plpgsql. */
  readonly validate: (fn: string) => string;
  /** `restrictedRoles` of `<fn>.attrs` as text[]. */
  readonly roles: (fn: string) => string;
}

export function noteRules(ctx: BlockSqlContext): NoteRules {
  const on = (column: keyof typeof NOTE_COLUMNS): boolean =>
    ctx.has("engagements", column);

  const e = (column: string): string => ctx.col("engagements", column);
  const l = (column: string): string => ctx.col("links", column);
  const categories = names(ctx, "noteCategories", NOTE_CATEGORIES);
  const lockTypes = names(ctx, "lockTypes", LOCK_TYPES);
  const hours = ctx.number("lockAfterHours", 24);

  if (!Number.isInteger(hours) || hours < 0 || hours > MAX_LOCK_HOURS) {
    throw new TypeError(
      `blocks.activities.options.lockAfterHours must be a whole number of hours from 0 to ${MAX_LOCK_HOURS}`,
    );
  }

  if (on("restrictedRoles") && !on("audience")) {
    throw new TypeError(
      "blocks.activities.columns.engagements.restrictedRoles needs audience",
    );
  }

  if (
    (on("markedErrorBy") || on("markedErrorReason")) &&
    !on("markedErrorAt")
  ) {
    throw new TypeError(
      "blocks.activities.columns.engagements.markedErrorBy and markedErrorReason need markedErrorAt",
    );
  }

  const readRestricted = ctx.permission(
    "readRestricted",
    moduleOperations("activities").readRestricted,
  );

  const guests =
    on("audience") && ctx.scope.guest("''", "''", "''", "read") !== "false";

  const hasRole = ctx.of("subjects").fn("has_subject_role");

  const linked = (p: string, condition: string): string =>
    `exists (select 1 from ${ctx.table("links")} nx where nx.${l("engagement")} = ${p}${e("id")} and ${condition})`;

  const memberRead = (p: string): string => {
    if (!on("audience")) {
      return "true";
    }

    const own = [
      `${p}${e("owner")} = (select auth.uid())`,
      ...(ctx.has("engagements", "createdBy")
        ? [`${p}${e("createdBy")} = (select auth.uid())`]
        : []),
    ];

    const role = on("restrictedRoles")
      ? [
          linked(
            p,
            `${hasRole}(nx.${l("subjectType")}, nx.${l("subjectId")}, ${p}${e("restrictedRoles")})`,
          ),
        ]
      : [];

    return `(${p}${e("audience")} <> 'restricted' or ${ctx.scope.check(`${p}${e("tenant")}`, readRestricted)} or ${[...own, ...role].join(" or ")})`;
  };

  const locked = (p: string): string => {
    const locks = [
      ...(on("lockedAt") ? [`${p}${e("lockedAt")} <= now()`] : []),
      ...(on("markedErrorAt") ? [`${p}${e("markedErrorAt")} is not null`] : []),
    ];

    return locks.length === 0 ? "false" : `(${locks.join(" or ")})`;
  };

  const lockAt = (type: string, from: string): string =>
    lockTypes.length === 0
      ? "null::timestamptz"
      : `case when ${type} = any (${textArray(lockTypes)}) then ${from} + interval '${hours} hours' end`;

  const attr = (fn: string, key: string): string =>
    `${fn}.attrs ->> ${sqlString(key)}`;

  const validate = (fn: string): string => {
    const audience = on("audience")
      ? `
  if nullif(${attr(fn, "audience")}, '') is not null and not (${attr(fn, "audience")} = any (${textArray(AUDIENCES)})) then
    ${fail("ACTIVITY_AUDIENCE_INVALID", `audience must be one of ${AUDIENCES.join(", ")}`, "22023")}
  end if;`
      : "";

    const roles = on("restrictedRoles")
      ? `
  if ${fn}.attrs ? 'restrictedRoles' and jsonb_typeof(${fn}.attrs -> 'restrictedRoles') not in ('array', 'null') then
    ${fail("ACTIVITY_AUDIENCE_INVALID", "restrictedRoles must be a list of record team roles", "22023")}
  end if;`
      : "";

    const category = on("category")
      ? `
  if nullif(${attr(fn, "category")}, '') is not null and not (${attr(fn, "category")} = any (${textArray(categories)})) then
    ${fail("ACTIVITY_CATEGORY_INVALID", `category must be one of ${categories.join(", ")}`, "22023")}
  end if;`
      : "";

    return `${audience}${roles}${category}`;
  };

  const roles = (fn: string): string =>
    `(select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(${fn}.attrs -> 'restrictedRoles') = 'array' then ${fn}.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r)`;

  const guestRead = (p: string): string =>
    guests
      ? `(${p}${e("audience")} = 'subject' and ${ctx.fn("engagement_guest_readable")}(${p}${e("id")}))`
      : "false";

  return { on, guests, memberRead, guestRead, locked, lockAt, validate, roles };
}

/** What the notes SQL borrows from the engagements module. */
export interface NotesSqlParts {
  readonly rules: NoteRules;
  /** Whether the caller may read row `x` (the read policy's rule). */
  readonly readable: (alias: string) => string;
  readonly editable: (alias: string) => string;
  readonly record: (
    event: string,
    id: string,
    type: string,
    tenant: string,
    extra?: string,
  ) => string;
  readonly row: (alias: string) => string;
  readonly subjectsOf: (id: string) => string;
  readonly write: string;
}

/**
 * The columns `NOTE_COLUMNS` the table has, added to an existing table, and the
 * index on `amends_id`.
 */
export function noteColumnsSql(ctx: BlockSqlContext): string {
  const t = ctx.table("engagements");
  const e = (column: string): string => ctx.col("engagements", column);

  const columns: readonly (readonly [
    keyof typeof NOTE_COLUMNS,
    (name: string) => string,
  ])[] = [
    [
      "audience",
      (x) =>
        `${x} text not null default 'team' check (${x} in (${AUDIENCES.map(sqlString).join(", ")}))`,
    ],
    ["restrictedRoles", (x) => `${x} text[]`],
    ["category", (x) => `${x} text check (length(${x}) between 1 and 63)`],
    ["lockedAt", (x) => `${x} timestamptz`],
    [
      "amends",
      (x) => `${x} uuid references ${t} (${e("id")}) on delete cascade`,
    ],
    ["goal", (x) => `${x} uuid`],
    ["markedErrorAt", (x) => `${x} timestamptz`],
    ["markedErrorBy", (x) => `${x} uuid`],
    [
      "markedErrorReason",
      (x) => `${x} text check (length(${x}) between 1 and 2000)`,
    ],
  ];

  const present = columns.filter(([column]) => ctx.has("engagements", column));

  if (present.length === 0) {
    return "";
  }

  return `
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
${present.map(([column, definition]) => `alter table ${t} add column if not exists ${definition(e(column))};`).join("\n")}${
    ctx.has("engagements", "amends")
      ? `\ncreate index if not exists ${ctx.naming.rename("engagements_amends_idx")} on ${t} (${e("amends")});`
      : ""
  }`;
}

/**
 * `engagement_guest_readable`, for the read policies: whether the caller
 * reaches a `subject` engagement as a guest of one of its records.
 */
export function noteGuestSql(ctx: BlockSqlContext, rules: NoteRules): string {
  const t = (table: string): string => ctx.table(table);
  const e = (column: string): string => ctx.col("engagements", column);
  const l = (column: string): string => ctx.col("links", column);
  const fn = (name: string): string => ctx.fn(name);

  return rules.guests
    ? `
-- Whether the caller reaches a subject engagement as a guest of one of its
-- records. Reads past the policies, for the read policies only.
create or replace function ${fn("engagement_guest_readable")}(engagement uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${t("engagements")} x
    join ${t("links")} k on k.${l("engagement")} = x.${e("id")}
    where x.${e("id")} = engagement_guest_readable.engagement
      and x.${e("audience")} = 'subject'
      and ${ctx.scope.guest(`k.${l("tenant")}`, `k.${l("subjectType")}`, `k.${l("subjectId")}`, "read")}
  )
$$;
${userGrant(`${fn("engagement_guest_readable")}(uuid)`)}`
    : "";
}

/**
 * `amend_activity` and `mark_activity_error`, each when the table has its
 * columns.
 */
export function notesSql(ctx: BlockSqlContext, parts: NotesSqlParts): string {
  const { rules, readable, editable, record, row, subjectsOf, write } = parts;
  const t = (table: string): string => ctx.table(table);
  const e = (column: string): string => ctx.col("engagements", column);
  const l = (column: string): string => ctx.col("links", column);
  const fn = (name: string): string => ctx.fn(name);
  const has = (column: string): boolean => ctx.has("engagements", column);
  const position = ctx.has("links", "position");

  const from = (column: string) => (): string => `v_from.${e(column)}`;

  const copied = (
    [
      ["tenant", from("tenant")],
      ["type", from("type")],
      ["title", from("title")],
      ["body", () => "v_body"],
      ["owner", () => "auth.uid()"],
      ["amends", from("id")],
      ["audience", from("audience")],
      ["restrictedRoles", from("restrictedRoles")],
      ["category", from("category")],
      ["goal", from("goal")],
      ["lockedAt", () => rules.lockAt(`v_from.${e("type")}::text`, "now()")],
      ["createdBy", () => "auth.uid()"],
    ] as const
  )
    .filter(([column]) => has(column))
    .map(([column, value]) => [column, value()] as const);

  const amend = rules.on("amends")
    ? `
-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function ${fn("amend_activity")}(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from ${t("engagements")};
  v_id uuid;
  v_body text := nullif(trim(amend_activity.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  select * into v_from from ${t("engagements")} x
  where x.${e("id")} = amend_activity.engagement and (${SERVICE_CALLER} or ${readable("x")});
  if v_from.${e("id")} is null then
    ${fail("ACTIVITY_NOT_FOUND", "no such engagement you can read", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.scope.can(`v_from.${e("tenant")}`, write)}) then
    ${fail("ACTIVITY_FORBIDDEN", "not allowed to amend engagements")}
  end if;
  if v_body is null then
    ${fail("ACTIVITY_BODY_REQUIRED", "an addendum needs a body", "23502")}
  end if;
  insert into ${t("engagements")} (${copied.map(([column]) => e(column)).join(", ")})
  values (${copied.map(([, value]) => value).join(", ")})
  returning ${e("id")} into v_id;
  insert into ${t("links")} (${l("tenant")}, ${l("engagement")}, ${l("subjectType")}, ${l("subjectId")}${position ? `, ${l("position")}` : ""})
  select k.${l("tenant")}, v_id, k.${l("subjectType")}, k.${l("subjectId")}${position ? `, k.${l("position")}` : ""}
  from ${t("links")} k where k.${l("engagement")} = v_from.${e("id")};
  v_subjects := ${subjectsOf("v_id")};
  v_first := v_subjects -> 0;
  ${record("activity.amended", "v_id", `v_from.${e("type")}::text`, `v_from.${e("tenant")}`, `'amendsId', v_from.${e("id")}`)}
  return (select ${row("x")} from ${t("engagements")} x where x.${e("id")} = v_id);
end;
$$;
${userGrant(`${fn("amend_activity")}(uuid, text)`)}
`
    : "";

  const sets = (): readonly string[] => [
    `${e("markedErrorAt")} = now()`,
    ...(has("markedErrorBy") ? [`${e("markedErrorBy")} = auth.uid()`] : []),
    ...(has("markedErrorReason")
      ? [`${e("markedErrorReason")} = v_reason`]
      : []),
    ...(has("lockedAt")
      ? [`${e("lockedAt")} = least(coalesce(x.${e("lockedAt")}, now()), now())`]
      : []),
  ];

  const markError = rules.on("markedErrorAt")
    ? `
-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function ${fn("mark_activity_error")}(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_activity_error.engagement;
  v_reason text := nullif(trim(mark_activity_error.reason), '');
  v_tenant ${ctx.idType};
  v_type text;
  v_subjects jsonb := ${subjectsOf("mark_activity_error.engagement")};
  v_first jsonb := v_subjects -> 0;
begin
  if v_reason is null then
    ${fail("ACTIVITY_REASON_REQUIRED", "say why the engagement is in error", "23502")}
  end if;
  if exists (select 1 from ${t("engagements")} x where x.${e("id")} = v_id and ${editable("x")} and x.${e("markedErrorAt")} is not null) then
    ${fail("ACTIVITY_ALREADY_MARKED_ERROR", "the engagement is already marked in error", "55000")}
  end if;
  update ${t("engagements")} x set
    ${sets().join(",\n    ")}
  where x.${e("id")} = v_id and ${editable("x")}
  returning x.${e("tenant")}, x.${e("type")}::text into v_tenant, v_type;
  if v_tenant is null then
    ${fail("ACTIVITY_NOT_FOUND", "no such engagement you can edit", "P0002")}
  end if;
  ${record("activity.error_marked", "v_id", "v_type", "v_tenant", "'reason', v_reason")}
  return (select ${row("x")} from ${t("engagements")} x where x.${e("id")} = v_id);
end;
$$;
${userGrant(`${fn("mark_activity_error")}(uuid, text)`)}
`
    : "";

  return `${amend}${markError}`;
}

export function notesContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  const rules = noteRules(ctx);

  return [
    ...(rules.guests && ctx.manages
      ? [
          {
            name: "engagement_guest_readable",
            args: ["uuid"],
            returns: "boolean",
          },
        ]
      : []),
    ...(rules.on("amends")
      ? [{ name: "amend_activity", args: ["uuid", "text"], returns: "jsonb" }]
      : []),
    ...(rules.on("markedErrorAt")
      ? [
          {
            name: "mark_activity_error",
            args: ["uuid", "text"],
            returns: "jsonb",
          },
        ]
      : []),
  ];
}
