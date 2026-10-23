import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { OPERATIONS } from "./permissions-model.ts";

const WHERE = "blocks.content.options";

const TYPE = /^[a-z][a-z0-9_-]{0,62}$/;
const LOCALE = /^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$/;
const CRON = /^\S+( \S+){4}$/;

/** The statuses an entry moves through. */
export const CONTENT_STATUSES = [
  "draft",
  "scheduled",
  "published",
  "archived",
] as const;

/** A slug: lowercase words joined by dashes, with `/` between segments. */
export const SLUG = "^[a-z0-9]+(?:[-/][a-z0-9]+)*$";

/** The largest entry body, in bytes of its JSON text. */
export const MAX_BODY = 1_000_000;

/** The SQL pieces the content files share. */
export interface ContentSql {
  readonly fn: (name: string) => string;
  /** A column of the entries table. */
  readonly e: (column: string) => string;
  readonly entries: string;
  /** The entries' subject type, after renames, as a SQL literal. */
  readonly subject: string;
  /** `options.types` as a SQL `text[]` literal. */
  readonly types: string;
  /** `options.locales` as a SQL `text[]` literal. */
  readonly locales: string;
  /** The default locale, the first of `options.locales`, as a SQL literal. */
  readonly defaultLocale: string;
  /** Whether publishing goes through the approvals block. */
  readonly approval: boolean;
  /** The approvals policy snapshot publishing opens, as JSON. */
  readonly policy: string;
  readonly versions: BlockSqlContext | undefined;
  readonly approvals: BlockSqlContext | undefined;
  /** The attachments context when the attachments block manages its table. */
  readonly attachments: BlockSqlContext | undefined;
  readonly attachmentsInstalled: boolean;
  readonly read: string;
  readonly write: string;
  readonly publish: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly missing: string;
  /**
   * Cancels the pending publish request of the draft in `row`, so a change
   * after the request needs a new one. Empty without approvals.
   */
  readonly withdraw: (row: string) => string;
  readonly json: (row: string) => string;
  /**
   * Records a `content_entry.*` event of an entries row; `false` leaves it out
   * of the audit log.
   */
  readonly record: (
    type: string,
    row: string,
    summary: string | false,
  ) => string;
}

function keysOf(
  ctx: BlockSqlContext,
  name: string,
  fallback: readonly string[],
  pattern: RegExp,
  what: string,
): readonly string[] {
  const values = ctx.list(name, fallback);

  if (values.length === 0) {
    throw new TypeError(`${WHERE}.${name} must name at least one ${what}`);
  }

  for (const value of values) {
    if (!pattern.test(value)) {
      throw new TypeError(
        `${WHERE}.${name}: "${value}" is not a valid ${what}`,
      );
    }
  }

  if (new Set(values).size !== values.length) {
    throw new TypeError(`${WHERE}.${name} lists a ${what} twice`);
  }

  return values;
}

/** `options.types`: the entry types, such as `page` and `post`. */
const contentTypes = (ctx: BlockSqlContext): readonly string[] =>
  keysOf(ctx, "types", ["page", "post"], TYPE, "type");

/** `options.locales`; the first is the default. */
const contentLocales = (ctx: BlockSqlContext): readonly string[] =>
  keysOf(ctx, "locales", ["en"], LOCALE, "locale");

/** `options.publishSchedule`, or undefined when it is empty. */
export function publishSchedule(ctx: BlockSqlContext): string | undefined {
  const schedule = ctx.text("publishSchedule", "*/5 * * * *").trim();

  if (schedule === "") {
    return undefined;
  }

  if (!CRON.test(schedule)) {
    throw new TypeError(
      `${WHERE}.publishSchedule must be a cron expression of five fields, or empty`,
    );
  }

  return schedule;
}

/** Whether publishing goes through approvals; throws when it can't. */
function requiresApproval(ctx: BlockSqlContext): boolean {
  if (!ctx.flag("requireApproval", false)) {
    return false;
  }

  if (!ctx.installed("approvals")) {
    throw new TypeError(
      `${WHERE}.requireApproval needs the approvals block installed`,
    );
  }

  if (ctx.of("approvals").mode === "custom") {
    throw new TypeError(
      `${WHERE}.requireApproval needs the approvals block's tables`,
    );
  }

  return true;
}

/**
 * `options.publishPolicy` as an approvals policy snapshot; defaults to one step
 * any other holder of the publish permission decides.
 */
function publishPolicy(ctx: BlockSqlContext, publishKey: string): string {
  const raw = ctx.option("publishPolicy") ?? {
    steps: [{ approvers: { permission: publishKey } }],
  };

  const policy = policyOf(
    ctx.naming.rename("content_entry"),
    "publish",
    raw,
    `${WHERE}.publishPolicy`,
  );

  if (policy.run !== undefined) {
    throw new TypeError(
      `${WHERE}.publishPolicy.run is not allowed; the final approval publishes the entry`,
    );
  }

  return policySnapshot(policy);
}

const textArray = (values: readonly string[]): string =>
  `array[${values.map((value) => sqlString(value)).join(", ")}]::text[]`;

const managed = (
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined =>
  ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;

export function contentSql(ctx: BlockSqlContext): ContentSql {
  const e = (column: string): string => ctx.col("entries", column);
  const types = contentTypes(ctx);
  const locales = contentLocales(ctx);
  const approvals = managed(ctx, "approvals");
  const attachments = managed(ctx, "attachments");
  const read = ctx.permission("read", OPERATIONS["content.read"]);

  const publishKey = ctx.permissionKey(
    "publish",
    OPERATIONS["content.publish"],
  );

  const approvalStatus =
    approvals === undefined
      ? () => "null::text"
      : (row: string) =>
          `(select r.${approvals.col("requests", "status")} from ${approvals.table("requests")} r where r.${approvals.col("requests", "id")} = ${row}.${e("approval")})`;

  return {
    fn: (name) => ctx.fn(name),
    e,
    entries: ctx.table("entries"),
    subject: sqlString(ctx.naming.rename("content_entry")),
    types: textArray(types),
    locales: textArray(locales),
    defaultLocale: sqlString(locales[0] ?? "en"),
    approval: requiresApproval(ctx),
    policy: publishPolicy(ctx, publishKey),
    versions: managed(ctx, "versions"),
    approvals,
    attachments,
    attachmentsInstalled: ctx.installed("attachments"),
    read,
    write: ctx.permission("write", OPERATIONS["content.write"]),
    publish: ctx.permission("publish", OPERATIONS["content.publish"]),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    invalid: (message) => fail("CONTENT_INVALID", message, "22023"),
    forbidden: (message) => fail("CONTENT_FORBIDDEN", message),
    missing: fail("CONTENT_NOT_FOUND", "no such content entry", "P0002"),
    withdraw: (row) =>
      approvals === undefined
        ? ""
        : `
  if ${row}.${e("status")} = 'draft' and ${row}.${e("approval")} is not null then
    update ${approvals.table("requests")} r set ${approvals.col("requests", "status")} = 'cancelled', ${approvals.col("requests", "decidedAt")} = now()
    where r.${approvals.col("requests", "id")} = ${row}.${e("approval")} and r.${approvals.col("requests", "status")} = 'pending';
  end if;`,
    json: (row) =>
      `jsonb_build_object('id', ${row}.${e("id")}, 'organizationId', ${row}.${e("tenant")}, 'type', ${row}.${e("type")}, 'locale', ${row}.${e("locale")}, 'slug', ${row}.${e("slug")}, 'title', ${row}.${e("title")}, 'summary', ${row}.${e("summary")}, 'body', ${row}.${e("body")}, 'status', ${row}.${e("status")}, 'publishAt', ${row}.${e("publishAt")}, 'publishedAt', ${row}.${e("publishedAt")}, 'authorId', ${row}.${e("author")}, 'translationGroupId', ${row}.${e("translationGroup")}, 'coverAttachmentId', ${row}.${e("cover")}, 'approvalId', ${row}.${e("approval")}, 'approvalStatus', ${approvalStatus(row)}, 'createdBy', ${row}.${e("createdBy")}, 'createdAt', ${row}.${e("createdAt")}, 'updatedAt', ${row}.${e("updatedAt")})`,
    record: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${e("tenant")}, 'id', ${row}.${e("id")}, 'type', ${row}.${e("type")}, 'locale', ${row}.${e("locale")}, 'slug', ${row}.${e("slug")}, 'status', ${row}.${e("status")}, 'translationGroupId', ${row}.${e("translationGroup")})`,
        subject: `'content-entries/' || ${row}.${e("id")}::text`,
        tenant: `${row}.${e("tenant")}`,
        audit:
          summary === false
            ? false
            : {
                category: "data",
                targetType: "content_entry",
                recordId: `${row}.${e("id")}::text`,
                targetLabel: `${row}.${e("title")}`,
                summary: sqlString(summary),
              },
      }),
  };
}
