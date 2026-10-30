import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import {
  representationActive,
  REPRESENTS,
} from "./contacts-representatives.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The lawful bases a purpose names (GDPR Art. 6(1)). */
export const LEGAL_BASES = [
  "consent",
  "contract",
  "legal_obligation",
  "vital_interest",
  "public_task",
  "legitimate_interest",
] as const;

/** The statuses a consent moves through. */
export const CONSENT_STATUSES = [
  "granted",
  "refused",
  "withdrawn",
  "expired",
] as const;

/** Who gave a consent: the data subject or a representative. */
export const GIVEN_BY = ["self", "representative"] as const;

/** A purpose key: lowercase words joined by `_`, `-` or `.`. */
export const PURPOSE_KEY = "^[a-z][a-z0-9_.-]{0,62}$";

/** The SQL pieces the consents files share. */
export interface ConsentsSql {
  readonly fn: (name: string) => string;
  /** A column of the purposes table. */
  readonly p: (column: string) => string;
  /** A column of the consents table. */
  readonly c: (column: string) => string;
  readonly has: (table: "purposes" | "consents", column: string) => boolean;
  /** `row.column`, or `null` when the table lacks the column. */
  readonly of: (
    table: "purposes" | "consents",
    row: string,
    column: string,
  ) => string;
  /** `value` as the type of a `typed` column. */
  readonly cast: (
    table: "purposes" | "consents",
    column: string,
    value: string,
  ) => string;
  readonly purposes: string;
  readonly consents: string;
  readonly read: string;
  readonly record: string;
  readonly manage: string;
  /** The service role, or a member of `tenant` holding `permission`. */
  readonly allowed: (tenant: string, permission: string) => string;
  /** `can_subject(type, id, 'read')`. */
  readonly canSubject: (type: string, id: string) => string;
  /**
   * True when the caller is a guest of `tenant` whose person represents record
   * `type`/`id` through a live `represents` link, with authority to act when
   * `act` is set. `false` without relations and contacts.
   */
  readonly representing: (
    tenant: string,
    type: string,
    id: string,
    act: boolean,
  ) => string;
  /**
   * The person (uuid) the guest caller acts through for record `type`/`id`, or
   * null. `null::uuid` without relations and contacts.
   */
  readonly representative: (tenant: string, type: string, id: string) => string;
  /**
   * True when person `contact` represents record `type`/`id` in `tenant` with
   * authority to act; with contacts but no relations, when the person is in
   * `tenant`; `true` without contacts.
   */
  readonly actsFor: (
    tenant: string,
    type: string,
    id: string,
    contact: string,
  ) => string;
  /**
   * Whether the caller reads the consents of record `type`/`id` in `tenant`:
   * the service role, a member with `consents.read` who reads the record, a
   * guest granted the record or representing it, or the record's own party.
   */
  readonly readable: (tenant: string, type: string, id: string) => string;
  /**
   * Whether the caller records or withdraws consents of the record: the service
   * role, a member with `consents.record` who reads it, its party or a
   * representative with authority to act.
   */
  readonly recordable: (tenant: string, type: string, id: string) => string;
  readonly signatures: BlockSqlContext | undefined;
  readonly forms: BlockSqlContext | undefined;
  readonly attachments: BlockSqlContext | undefined;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly missing: string;
  readonly purposeMissing: string;
  readonly purposeJson: (row: string) => string;
  /** A consents row with its purpose row as JSON, `active` included. */
  readonly consentJson: (row: string, purpose: string) => string;
  /** SQL that is true when the consents row `row` is in force. */
  readonly active: (row: string) => string;
  readonly recordPurpose: (
    type: string,
    row: string,
    summary: string,
  ) => string;
  readonly recordConsent: (
    type: string,
    row: string,
    purpose: string,
    summary: string,
  ) => string;
}

const managed = (
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined =>
  ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;

export function consentsSql(ctx: BlockSqlContext): ConsentsSql {
  const keys = moduleOperations("consents");
  const p = (column: string): string => ctx.col("purposes", column);
  const c = (column: string): string => ctx.col("consents", column);

  const has = (table: "purposes" | "consents", column: string): boolean =>
    ctx.has(table, column);

  const of = (
    table: "purposes" | "consents",
    row: string,
    column: string,
  ): string =>
    has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";

  const canSubjectFn = ctx.of("subjects").fn("can_subject");

  const canSubject = (type: string, id: string): string =>
    `coalesce(${canSubjectFn}(${type}, ${id}, 'read'), false)`;

  const contacts = managed(ctx, "contacts");

  const relations =
    contacts !== undefined && ctx.installed("relations")
      ? ctx.of("relations")
      : undefined;

  const person = sqlString(ctx.naming.rename("person"));

  const links = (
    tenant: string,
    type: string,
    id: string,
    act: boolean,
  ): string => {
    if (relations === undefined) {
      return "";
    }

    const r = (column: string): string =>
      `r.${relations.col("relations", column)}`;

    return `from ${relations.table("relations")} r
      where ${r("kind")} = ${sqlString(REPRESENTS)} and ${r("sourceType")} = ${person}
        and ${r("tenant")}::text = (${tenant})::text
        and ${r("targetType")} = ${type} and ${r("targetId")} = (${id})::text
        and ${act ? `${r("data")} ->> 'authority' = 'act'` : `${r("data")} ->> 'authority' in ('inform', 'act')`}
        and ${representationActive(r("data"))}`;
  };

  const sourceId = (): string =>
    relations === undefined
      ? "null"
      : `r.${relations.col("relations", "sourceId")}`;

  const representing = (
    tenant: string,
    type: string,
    id: string,
    act: boolean,
  ): string =>
    relations === undefined
      ? "false"
      : `exists (select 1 ${links(tenant, type, id, act)}
        and ${ctx.scope.guestParty(tenant, person, sourceId())})`;

  const representative = (tenant: string, type: string, id: string): string =>
    relations === undefined
      ? "null::uuid"
      : `(select ${sourceId()}::uuid ${links(tenant, type, id, true)}
        and ${ctx.scope.guestParty(tenant, person, sourceId())}
      order by ${sourceId()} limit 1)`;

  const actsFor = (
    tenant: string,
    type: string,
    id: string,
    contact: string,
  ): string => {
    if (relations !== undefined) {
      return `exists (select 1 ${links(tenant, type, id, true)}
        and ${sourceId()} = (${contact})::text)`;
    }

    if (contacts !== undefined) {
      return `exists (select 1 from ${contacts.table("people")} x where x.${contacts.col("people", "id")} = ${contact} and x.${contacts.col("people", "tenant")}::text = (${tenant})::text)`;
    }

    return "true";
  };

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const read = ctx.permission("read", keys.read);
  const record = ctx.permission("record", keys.record);

  const guestOf = (tenant: string, type: string, id: string): string =>
    ctx.scope.guestParty(tenant, type, id);

  const readable = (tenant: string, type: string, id: string): string =>
    `(${SERVICE_CALLER}
      or (${ctx.can("tenant", tenant, read)} and ${canSubject(type, id)})
      or ${ctx.scope.guest(tenant, type, id, "read")}
      or ${guestOf(tenant, type, id)}
      or ${representing(tenant, type, id, false)})`;

  const recordable = (tenant: string, type: string, id: string): string =>
    `(${SERVICE_CALLER}
      or (${ctx.can("tenant", tenant, record)} and ${canSubject(type, id)})
      or ${guestOf(tenant, type, id)}
      or ${representing(tenant, type, id, true)})`;

  const active = (row: string): string =>
    `(${row}.${c("status")} = 'granted' and (${row}.${c("validUntil")} is null or ${row}.${c("validUntil")} > now()))`;

  const purposeJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'key', ${row}.${p("key")}, 'title', ${row}.${p("title")}, 'description', ${of("purposes", row, "description")}, 'legalBasis', ${row}.${p("legalBasis")}, 'version', ${row}.${p("version")}, 'requiresSignature', ${row}.${p("requiresSignature")}, 'validMonths', ${row}.${p("validMonths")}, 'archivedAt', ${row}.${p("archivedAt")}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${of("purposes", row, "updatedAt")})`;

  const consentJson = (row: string, purpose: string): string =>
    `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'purposeId', ${row}.${c("purpose")}, 'purposeKey', ${purpose}.${p("key")}, 'purposeTitle', ${purpose}.${p("title")}, 'purposeVersion', ${purpose}.${p("version")}, 'legalBasis', ${purpose}.${p("legalBasis")}, 'subjectType', ${row}.${c("subjectType")}, 'subjectId', ${row}.${c("subjectId")}, 'givenBy', ${row}.${c("givenBy")}, 'givenByContactId', ${row}.${c("givenByContact")}, 'givenByUserId', ${row}.${c("givenByUser")}, 'status', ${row}.${c("status")}, 'scope', coalesce(${of("consents", row, "scope")}, '{}'::jsonb), 'grantedAt', ${row}.${c("grantedAt")}, 'validUntil', ${row}.${c("validUntil")}, 'withdrawnAt', ${row}.${c("withdrawnAt")}, 'withdrawnReason', ${of("consents", row, "withdrawnReason")}, 'signatureId', ${of("consents", row, "signature")}, 'submissionId', ${of("consents", row, "submission")}, 'attachmentId', ${of("consents", row, "attachment")}, 'createdBy', ${of("consents", row, "createdBy")}, 'createdAt', ${row}.${c("createdAt")}, 'active', ${active(row)})`;

  return {
    fn: (name) => ctx.fn(name),
    p,
    c,
    has,
    of,
    cast: (table, column, value) => ctx.cast(table, column, value),
    purposes: ctx.table("purposes"),
    consents: ctx.table("consents"),
    read,
    record,
    manage: ctx.permission("manage", keys.manage),
    allowed,
    canSubject,
    representing,
    representative,
    actsFor,
    readable,
    recordable,
    signatures: managed(ctx, "signatures"),
    forms: managed(ctx, "forms"),
    attachments: managed(ctx, "attachments"),
    invalid: (message) => fail("CONSENT_INVALID", message, "22023"),
    forbidden: (message) => fail("CONSENT_FORBIDDEN", message),
    missing: fail("CONSENT_NOT_FOUND", "no such consent", "P0002"),
    purposeMissing: fail(
      "CONSENT_PURPOSE_NOT_FOUND",
      "no such consent purpose",
      "P0002",
    ),
    purposeJson,
    consentJson,
    active,
    recordPurpose: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${p("tenant")}, 'purposeId', ${row}.${p("id")}, 'key', ${row}.${p("key")}, 'version', ${row}.${p("version")})`,
        subject: `'consent-purposes/' || ${row}.${p("id")}::text`,
        tenant: `${row}.${p("tenant")}`,
        audit: {
          category: "data",
          targetType: "consent_purpose",
          recordId: `${row}.${p("id")}::text`,
          targetLabel: `${row}.${p("title")}`,
          summary: sqlString(summary),
        },
      }),
    recordConsent: (type, row, purpose, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${c("tenant")}, 'consentId', ${row}.${c("id")}, 'purposeId', ${row}.${c("purpose")}, 'purposeKey', ${purpose}.${p("key")}, 'subjectType', ${row}.${c("subjectType")}, 'subjectId', ${row}.${c("subjectId")}, 'status', ${row}.${c("status")}, 'givenBy', ${row}.${c("givenBy")})`,
        subject: `'consents/' || ${row}.${c("id")}::text`,
        tenant: `${row}.${c("tenant")}`,
        audit: {
          category: "data",
          targetType: "consent",
          recordId: `${row}.${c("id")}::text`,
          targetLabel: `${purpose}.${p("title")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
