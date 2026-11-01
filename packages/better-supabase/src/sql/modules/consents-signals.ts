import type { BlockSqlContext } from "../context.ts";
import type { ConsentsSql } from "./consents-sql.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, lockTable, userGrant } from "../shared.ts";
import { subjectTenant } from "../subject-check-sql.ts";
import { consentsSql } from "./consents-sql.ts";

/** The signals a record can carry as consent evidence. */
const SIGNAL_KINDS = ["gpc", "tcf", "gpp"] as const;

/** The IAB TCF policy version that TCF v2.2 introduced. */
const TCF_V22_POLICY = 4;

/**
 * The bit positions of a TC string's core segment (IAB TCF v2.2, "Transparency
 * and Consent String with Global Vendor List Format"), as `[start, length]`
 * with `start` counting from 1.
 */
const TC_FIELDS = {
  version: [1, 6],
  created: [7, 36],
  lastUpdated: [43, 36],
  cmpId: [79, 12],
  cmpVersion: [91, 12],
  consentScreen: [103, 6],
  consentLanguage: [109, 12],
  vendorListVersion: [121, 12],
  tcfPolicyVersion: [133, 6],
  isServiceSpecific: [139, 1],
  useNonStandardTexts: [140, 1],
  specialFeatureOptIns: [141, 12],
  purposesConsent: [153, 24],
  purposesLiTransparency: [177, 24],
  purposeOneTreatment: [201, 1],
  publisherCc: [202, 12],
} as const;

/** The core segment's length in bits, up to the vendor section. */
const TC_CORE_BITS = 213;

/** The base64url alphabet; a character's position is its 6-bit value. */
const ALPHABET =
  "'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'";

const bits = (field: keyof typeof TC_FIELDS): string => {
  const [start, length] = TC_FIELDS[field];

  return `substring(v_bits from ${start} for ${length})::bit(${length})::bigint`;
};

const flags = (field: keyof typeof TC_FIELDS): string => {
  const [start, length] = TC_FIELDS[field];

  return `(select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from generate_series(1, ${length}) k where substring(v_bits from ${start - 1} + k for 1) = '1')`;
};

const instant = (field: keyof typeof TC_FIELDS): string =>
  `to_jsonb(to_timestamp(${bits(field)} / 10.0))`;

/**
 * A function that parses the core segment of an IAB TCF v2 TC string into JSON:
 * the header, the language, the policy version and the purposes and special
 * features as lists of ids. The vendor sections stay unread. It raises
 * `invalid_parameter_value` for a string that isn't a TCF v2 core segment.
 */
function tcParserSql(name: string): string {
  const invalid = (message: string): string =>
    `raise exception '${message}' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID'`;

  return `create or replace function ${name}(tc_string text)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_core text := split_part(coalesce(tc_string, ''), '.', 1);
  v_bits text := '';
  i integer;
begin
  if v_core !~ '^[A-Za-z0-9_-]{36,}$' then
    ${invalid("a TC string is base64url text of at least 36 characters")};
  end if;
  for i in 1 .. length(v_core) loop
    v_bits := v_bits || (strpos(${ALPHABET}, substr(v_core, i, 1)) - 1)::bit(6)::text;
  end loop;
  if length(v_bits) < ${TC_CORE_BITS} then
    ${invalid("the TC string is shorter than a core segment")};
  end if;
  if ${bits("version")} <> 2 then
    ${invalid("only TCF v2 TC strings are supported")};
  end if;
  return jsonb_build_object(
    'version', ${bits("version")},
    'created', ${instant("created")},
    'lastUpdated', ${instant("lastUpdated")},
    'cmpId', ${bits("cmpId")},
    'cmpVersion', ${bits("cmpVersion")},
    'consentScreen', ${bits("consentScreen")},
    'consentLanguage', chr(65 + (substring(v_bits from 109 for 6)::bit(6)::int)) || chr(65 + (substring(v_bits from 115 for 6)::bit(6)::int)),
    'vendorListVersion', ${bits("vendorListVersion")},
    'tcfPolicyVersion', ${bits("tcfPolicyVersion")},
    'tcfV22', ${bits("tcfPolicyVersion")} >= ${TCF_V22_POLICY},
    'isServiceSpecific', substring(v_bits from ${TC_FIELDS.isServiceSpecific[0]} for 1) = '1',
    'useNonStandardTexts', substring(v_bits from ${TC_FIELDS.useNonStandardTexts[0]} for 1) = '1',
    'specialFeatureOptIns', ${flags("specialFeatureOptIns")},
    'purposesConsent', ${flags("purposesConsent")},
    'purposesLiTransparency', ${flags("purposesLiTransparency")},
    'purposeOneTreatment', substring(v_bits from ${TC_FIELDS.purposeOneTreatment[0]} for 1) = '1',
    'publisherCc', chr(65 + (substring(v_bits from 202 for 6)::bit(6)::int)) || chr(65 + (substring(v_bits from 208 for 6)::bit(6)::int))
  );
end;
$$;`;
}

/**
 * A function that reads the header of a Global Privacy Platform string
 * (`DBABM~section~section`): the type (3) and the version (1), and keeps the
 * sections as given. It raises for anything else.
 */
function gppParserSql(name: string): string {
  const invalid = (message: string): string =>
    `raise exception '${message}' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID'`;

  return `create or replace function ${name}(gpp_string text)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_header text := split_part(coalesce(gpp_string, ''), '~', 1);
  v_bits text := '';
  i integer;
  v_sections jsonb;
begin
  if v_header !~ '^[A-Za-z0-9_-]{4,}$' then
    ${invalid("a GPP string starts with a base64url header")};
  end if;
  for i in 1 .. length(v_header) loop
    v_bits := v_bits || (strpos(${ALPHABET}, substr(v_header, i, 1)) - 1)::bit(6)::text;
  end loop;
  if length(v_bits) < 12 or substring(v_bits from 1 for 6)::bit(6)::int <> 3 then
    ${invalid("the GPP header has type 3")};
  end if;
  select coalesce(jsonb_agg(s order by n), '[]'::jsonb) into v_sections
  from unnest(string_to_array(gpp_string, '~')) with ordinality as t(s, n)
  where n > 1;
  return jsonb_build_object(
    'type', substring(v_bits from 1 for 6)::bit(6)::int,
    'version', substring(v_bits from 7 for 6)::bit(6)::int,
    'sections', v_sections
  );
end;
$$;`;
}

/** The signal and receipt tables. */
export function consentsSignalTables(
  ctx: BlockSqlContext,
  q: ConsentsSql,
): string {
  if (!ctx.manages) {
    return "";
  }

  const signals = ctx.table("signals");
  const receipts = ctx.table("receipts");
  const s = (column: string): string => ctx.col("signals", column);
  const r = (column: string): string => ctx.col("receipts", column);
  const canSubject = ctx.of("subjects").fn("can_subject");
  const kinds = SIGNAL_KINDS.map((kind) => `'${kind}'`).join(", ");

  const name = (table: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(table).name}_${suffix}`);

  return `
-- A signal a browser or consent platform sent for a record: the Sec-GPC header,
-- an IAB TCF v2.2 TC string or a GPP string, with what was parsed from it.
create table if not exists ${signals} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("subjectType")} text not null,
  ${s("subjectId")} text not null,
  ${s("kind")} text not null check (${s("kind")} in (${kinds})),
  ${s("raw")} text not null check (length(${s("raw")}) between 1 and 8192),
  ${s("parsed")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${s("parsed")}) = 'object'),
  ${s("consents")} uuid[] not null default '{}',
  ${s("createdBy")} uuid,
  ${s("receivedAt")} timestamptz not null default now()
);
create index if not exists ${name("signals", "subject_idx")} on ${signals} (${s("tenant")}, ${s("subjectType")}, ${s("subjectId")}, ${s("receivedAt")} desc);
${lockTable(signals, { read: true })}
${renderPolicy(makePolicy({ table: signals, name: name("signals", "read"), command: "select", roles: ["authenticated"], using: `(${ctx.scope.check(s("tenant"), q.read)} and ${canSubject}(${s("subjectType")}, ${s("subjectId")}, 'read')) or ${s("createdBy")} = (select auth.uid())` }), { drop: true, target: signals })}

-- A receipt for one consent decision: the document handed to the person, with
-- the SHA-256 of its text. One receipt per consent and status, never changed.
create table if not exists ${receipts} (
  ${r("id")} uuid primary key,
  ${r("tenant")} ${ctx.idType} not null,
  ${r("subjectType")} text not null,
  ${r("subjectId")} text not null,
  ${r("consent")} uuid not null references ${q.consents} (${q.c("id")}) on delete cascade,
  ${r("status")} text not null,
  ${r("receipt")} jsonb not null check (jsonb_typeof(${r("receipt")}) = 'object'),
  ${r("digest")} text not null check (${r("digest")} ~ '^[0-9a-f]{64}$'),
  ${r("issuedAt")} timestamptz not null default now(),
  unique (${r("consent")}, ${r("status")})
);
create index if not exists ${name("receipts", "tenant_idx")} on ${receipts} (${r("tenant")}, ${r("issuedAt")} desc);
${lockTable(receipts, { read: true })}
${renderPolicy(makePolicy({ table: receipts, name: name("receipts", "read"), command: "select", roles: ["authenticated"], using: `${ctx.scope.check(r("tenant"), q.read)} and ${canSubject}(${r("subjectType")}, ${r("subjectId")}, 'read')` }), { drop: true, target: receipts })}
`;
}

/** The signal and receipt functions. */
export function consentsSignalFunctions(ctx: BlockSqlContext): string {
  const q = consentsSql(ctx);
  const { fn, c, p, purposes, consents } = q;
  const signals = ctx.table("signals");
  const receipts = ctx.table("receipts");
  const s = (column: string): string => ctx.col("signals", column);
  const r = (column: string): string => ctx.col("receipts", column);

  const tenant = (func: string): string =>
    subjectTenant(ctx, `${func}.subject_type`, `${func}.subject_id`);

  const signalJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'subjectType', ${row}.${s("subjectType")}, 'subjectId', ${row}.${s("subjectId")}, 'kind', ${row}.${s("kind")}, 'raw', ${row}.${s("raw")}, 'parsed', ${row}.${s("parsed")}, 'consentIds', to_jsonb(${row}.${s("consents")}), 'receivedAt', ${row}.${s("receivedAt")})`;

  const receiptJson = (row: string): string =>
    `(${row}.${r("receipt")} || jsonb_build_object('digest', ${row}.${r("digest")}))`;

  return `-- Parses the core segment of an IAB TCF v2.2 TC string.
${tcParserSql(fn("parse_tc_string"))}
revoke execute on function ${fn("parse_tc_string")}(text) from public, anon, authenticated;

-- Reads the header of a GPP string and keeps its sections.
${gppParserSql(fn("parse_gpp_string"))}
revoke execute on function ${fn("parse_gpp_string")}(text) from public, anon, authenticated;

-- Records a signal for record subject_type/subject_id as consent evidence.
-- kind gpc: value is the Sec-GPC header value, 1, and purpose_keys names the
-- purposes it opts out of; each gets a refused consent. kind tcf or gpp: value
-- is the string, parsed and kept; consent_id optionally ties it to a consent
-- of the same record. The raw value is kept either way.
create or replace function ${fn("record_consent_signal")}(
  subject_type text,
  subject_id text,
  kind text,
  value text,
  purpose_keys text[] default '{}',
  consent_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${ctx.idType} := (${tenant("record_consent_signal")})::${ctx.idType};
  v_value text := trim(coalesce(record_consent_signal.value, ''));
  v_keys text[] := coalesce(record_consent_signal.purpose_keys, '{}');
  v_parsed jsonb;
  v_key text;
  v_ids uuid[] := '{}';
  v_decision jsonb;
  v_row ${signals};
begin
  if v_tenant is null or not ${q.recordable("v_tenant", "record_consent_signal.subject_type", "record_consent_signal.subject_id")} then
    ${q.forbidden("not allowed to record a consent signal for this record")}
  end if;
  if record_consent_signal.kind is null or record_consent_signal.kind not in (${SIGNAL_KINDS.map((kind) => `'${kind}'`).join(", ")}) then
    ${fail("CONSENT_SIGNAL_INVALID", "kind is gpc, tcf or gpp", "22023")}
  end if;
  if length(v_value) not between 1 and 8192 then
    ${fail("CONSENT_SIGNAL_INVALID", "value is 1 to 8192 characters", "22023")}
  end if;
  if record_consent_signal.kind = 'gpc' then
    if v_value <> '1' then
      ${fail("CONSENT_SIGNAL_INVALID", "the Sec-GPC header is 1 when the person opts out", "22023")}
    end if;
    if cardinality(v_keys) = 0 then
      ${fail("CONSENT_SIGNAL_INVALID", "purpose_keys names the purposes the signal opts out of", "22023")}
    end if;
    if record_consent_signal.consent_id is not null then
      ${fail("CONSENT_SIGNAL_INVALID", "a Sec-GPC signal creates its own consents", "22023")}
    end if;
    v_parsed := jsonb_build_object('header', 'Sec-GPC', 'optOut', true, 'purposeKeys', to_jsonb(v_keys));
    foreach v_key in array v_keys loop
      v_decision := ${fn("record_consent")}(record_consent_signal.subject_type, record_consent_signal.subject_id, v_key, 'refused');
      v_ids := v_ids || (v_decision ->> 'id')::uuid;
    end loop;
  else
    if cardinality(v_keys) > 0 then
      ${fail("CONSENT_SIGNAL_INVALID", "purpose_keys applies to a Sec-GPC signal only", "22023")}
    end if;
    v_parsed := case record_consent_signal.kind
      when 'tcf' then ${fn("parse_tc_string")}(v_value)
      else ${fn("parse_gpp_string")}(v_value)
    end;
    if record_consent_signal.consent_id is not null then
      if not exists (
        select 1 from ${consents} x
        where x.${c("id")} = record_consent_signal.consent_id and x.${c("tenant")} = v_tenant
          and x.${c("subjectType")} = record_consent_signal.subject_type and x.${c("subjectId")} = record_consent_signal.subject_id
      ) then
        ${q.missing}
      end if;
      v_ids := array[record_consent_signal.consent_id];
    end if;
  end if;
  insert into ${signals} (${s("tenant")}, ${s("subjectType")}, ${s("subjectId")}, ${s("kind")}, ${s("raw")}, ${s("parsed")}, ${s("consents")}, ${s("createdBy")})
  values (v_tenant, record_consent_signal.subject_type, record_consent_signal.subject_id, record_consent_signal.kind, v_value, v_parsed, v_ids, auth.uid())
  returning * into v_row;
  ${ctx.record({
    type: "consent_signal.recorded",
    payload: `jsonb_build_object('organizationId', v_row.${s("tenant")}, 'signalId', v_row.${s("id")}, 'kind', v_row.${s("kind")}, 'subjectType', v_row.${s("subjectType")}, 'subjectId', v_row.${s("subjectId")})`,
    subject: `'consent-signals/' || v_row.${s("id")}::text`,
    tenant: `v_row.${s("tenant")}`,
    audit: false,
  })}
  return ${signalJson("v_row")};
end;
$$;
${userGrant(`${fn("record_consent_signal")}(text, text, text, text, text[], uuid)`)}

-- The signals recorded for a record, the newest first.
create or replace function ${fn("list_consent_signals")}(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${ctx.idType} := (${tenant("list_consent_signals")})::${ctx.idType};
begin
  if v_tenant is null or not ${q.readable("v_tenant", "list_consent_signals.subject_type", "list_consent_signals.subject_id")} then
    ${q.forbidden("not allowed to read the consent signals of this record")}
  end if;
  return (
    select coalesce(jsonb_agg(${signalJson("x")} order by x.${s("receivedAt")} desc, x.${s("id")}), '[]'::jsonb)
    from ${signals} x
    where x.${s("tenant")} = v_tenant
      and x.${s("subjectType")} = list_consent_signals.subject_type and x.${s("subjectId")} = list_consent_signals.subject_id
  );
end;
$$;
${userGrant(`${fn("list_consent_signals")}(text, text)`)}

-- Issues the receipt for a consent decision: who, what, when, on which
-- purpose version and with which evidence, plus the SHA-256 of its text. The
-- same consent and status give the same receipt back; a withdrawal is a
-- second receipt.
create or replace function ${fn("issue_consent_receipt")}(consent_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${consents};
  v_purpose ${purposes};
  v_receipt ${receipts};
  v_id uuid := gen_random_uuid();
  v_issued timestamptz := now();
  v_doc jsonb;
begin
  select * into v_row from ${consents} x where x.${c("id")} = issue_consent_receipt.consent_id;
  if not found or not ${q.readable(`v_row.${c("tenant")}`, `v_row.${c("subjectType")}`, `v_row.${c("subjectId")}`)} then
    ${q.missing}
  end if;
  select * into v_receipt from ${receipts} x where x.${r("consent")} = v_row.${c("id")} and x.${r("status")} = v_row.${c("status")};
  if found then
    return ${receiptJson("v_receipt")};
  end if;
  select * into v_purpose from ${purposes} x where x.${p("id")} = v_row.${c("purpose")};
  v_doc := jsonb_build_object(
    'format', 'better-supabase/consent-receipt@1',
    'receiptId', v_id,
    'issuedAt', v_issued,
    'organizationId', v_row.${c("tenant")},
    'subject', jsonb_build_object('type', v_row.${c("subjectType")}, 'id', v_row.${c("subjectId")}),
    'purpose', jsonb_build_object('key', v_purpose.${p("key")}, 'title', v_purpose.${p("title")}, 'version', v_purpose.${p("version")}, 'legalBasis', v_purpose.${p("legalBasis")}),
    'consent', jsonb_build_object('id', v_row.${c("id")}, 'status', v_row.${c("status")}, 'givenBy', v_row.${c("givenBy")}, 'grantedAt', v_row.${c("grantedAt")}, 'validUntil', v_row.${c("validUntil")}, 'withdrawnAt', v_row.${c("withdrawnAt")}, 'scope', coalesce(${q.of("consents", "v_row", "scope")}, '{}'::jsonb)),
    'evidence', jsonb_build_object(
      'signatureId', ${q.of("consents", "v_row", "signature")},
      'submissionId', ${q.of("consents", "v_row", "submission")},
      'attachmentId', ${q.of("consents", "v_row", "attachment")},
      'signals', (select coalesce(jsonb_agg(jsonb_build_object('id', y.${s("id")}, 'kind', y.${s("kind")}, 'receivedAt', y.${s("receivedAt")}) order by y.${s("receivedAt")}, y.${s("id")}), '[]'::jsonb) from ${signals} y where v_row.${c("id")} = any(y.${s("consents")}))
    )
  );
  insert into ${receipts} (${r("id")}, ${r("tenant")}, ${r("subjectType")}, ${r("subjectId")}, ${r("consent")}, ${r("status")}, ${r("receipt")}, ${r("digest")}, ${r("issuedAt")})
  values (v_id, v_row.${c("tenant")}, v_row.${c("subjectType")}, v_row.${c("subjectId")}, v_row.${c("id")}, v_row.${c("status")}, v_doc, encode(sha256(convert_to(v_doc::text, 'UTF8')), 'hex'), v_issued)
  returning * into v_receipt;
  ${ctx.record({
    type: "consent_receipt.issued",
    payload: `jsonb_build_object('organizationId', v_receipt.${r("tenant")}, 'receiptId', v_receipt.${r("id")}, 'consentId', v_receipt.${r("consent")}, 'status', v_receipt.${r("status")}, 'subjectType', v_row.${c("subjectType")}, 'subjectId', v_row.${c("subjectId")})`,
    subject: `'consent-receipts/' || v_receipt.${r("id")}::text`,
    tenant: `v_receipt.${r("tenant")}`,
    audit: false,
  })}
  return ${receiptJson("v_receipt")};
end;
$$;
${userGrant(`${fn("issue_consent_receipt")}(uuid)`)}

-- The receipts of a record's consents, the newest first.
create or replace function ${fn("list_consent_receipts")}(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${ctx.idType} := (${tenant("list_consent_receipts")})::${ctx.idType};
begin
  if v_tenant is null or not ${q.readable("v_tenant", "list_consent_receipts.subject_type", "list_consent_receipts.subject_id")} then
    ${q.forbidden("not allowed to read the consent receipts of this record")}
  end if;
  return (
    select coalesce(jsonb_agg(${receiptJson("x")} order by x.${r("issuedAt")} desc, x.${r("id")}), '[]'::jsonb)
    from ${receipts} x
    where x.${r("tenant")} = v_tenant
      and x.${r("subjectType")} = list_consent_receipts.subject_type and x.${r("subjectId")} = list_consent_receipts.subject_id
  );
end;
$$;
${userGrant(`${fn("list_consent_receipts")}(text, text)`)}
`;
}
