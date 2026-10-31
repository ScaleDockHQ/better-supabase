import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { DriveKit } from "./drive-kit.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { sequenceFormatOf, withFixedNumber } from "../numbering-sql.ts";
import {
  activeMembership,
  ensureCheck,
  fail,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { driveSubjectType, READ_ONLY_GUARD } from "./drive-kit.ts";
import { lockGuard } from "./drive-locks.ts";
import { DOCUMENT_COLUMNS } from "./drive-names.ts";

const TYPE = /^[a-z][a-z0-9_-]{0,62}$/u;

const DEFAULT_REVIEW_MONTHS = 12;

/** The blocks `options.control` builds on. */
const NEEDS = ["numbering", "versions", "approvals", "state-machine"] as const;

/** The approvals action a document's release request uses. */
const RELEASE = "'release'";

/** `blocks.drive.options.control`, checked. */
export interface DriveControl {
  readonly types: readonly string[];
  /** The number format of the types that set `numberFormat`, by type. */
  readonly numberFormats: Readonly<Record<string, string>>;
  readonly reviewMonths: number;
  /** The role that obsoletes a document; the share role by default. */
  readonly releaseRole: string | undefined;
}

/**
 * `options.control` of the drive in `ctx`, or undefined when the app keeps no
 * controlled documents. Throws a TypeError for a bad value, or, with the
 * drive-files context `files`, for a block it needs that isn't installed.
 */
export function driveControl(
  ctx: BlockSqlContext,
  files?: BlockSqlContext,
): DriveControl | undefined {
  const raw = ctx.option("control");

  if (raw === undefined || raw === null) {
    return undefined;
  }

  const where = "blocks.drive.options.control";

  if (!isRecord(raw)) {
    throw new TypeError(
      `${where} must be { types, reviewMonths, releaseRole }`,
    );
  }

  const entries: unknown = raw["types"];

  const typeNames = Array.isArray(entries)
    ? entries.map((entry: unknown) => (isRecord(entry) ? entry["name"] : entry))
    : [];

  if (
    !Array.isArray(entries) ||
    entries.length === 0 ||
    !typeNames.every((type) => typeof type === "string" && TYPE.test(type)) ||
    new Set(typeNames).size !== typeNames.length
  ) {
    throw new TypeError(
      `${where}.types must list distinct document types in lowercase, such as sop, or { name, numberFormat }`,
    );
  }

  const types = typeNames.map(String);
  const numberFormats: Record<string, string> = {};

  // SAFETY: the check above proved `entries` is an array.
  for (const entry of entries as readonly unknown[]) {
    if (!isRecord(entry) || entry["numberFormat"] === undefined) {
      continue;
    }

    const format = entry["numberFormat"];

    if (
      typeof format !== "string" ||
      format.length === 0 ||
      format.length > 80 ||
      !/\{n(?::[0-9]+)?\}/.test(format)
    ) {
      throw new TypeError(
        `${where}.types[${String(entry["name"])}].numberFormat must be a short template with {n}, such as SOP-{n:4}`,
      );
    }

    numberFormats[String(entry["name"])] = format;
  }

  const reviewMonths = raw["reviewMonths"] ?? DEFAULT_REVIEW_MONTHS;

  if (
    typeof reviewMonths !== "number" ||
    !Number.isInteger(reviewMonths) ||
    reviewMonths < 1 ||
    reviewMonths > 120
  ) {
    throw new TypeError(
      `${where}.reviewMonths must be an integer from 1 to 120`,
    );
  }

  const releaseRole = raw["releaseRole"];

  if (releaseRole !== undefined && typeof releaseRole !== "string") {
    throw new TypeError(`${where}.releaseRole must be a drive role`);
  }

  const missing = NEEDS.filter(
    (module) =>
      files !== undefined &&
      (!files.installed(module) || files.of(module).mode === "custom"),
  );

  if (missing.length > 0) {
    throw new TypeError(`${where} needs the ${missing.join(", ")} blocks`);
  }

  const columns = DOCUMENT_COLUMNS.filter(
    (column) => !ctx.has("nodes", column),
  );

  if (columns.length > 0) {
    throw new TypeError(
      `${where} needs the drive_nodes columns ${columns.join(", ")}`,
    );
  }

  return { types, numberFormats, reviewMonths, releaseRole };
}

/** The functions `options.control` adds to the drive-files contract. */
export const DOCUMENT_FUNCTIONS: readonly BlockSqlContractFunction[] = [
  {
    name: "drive_document_save",
    args: ["uuid", "text", "uuid", "integer"],
    returns: "jsonb",
  },
  {
    name: "drive_document_submit",
    args: ["uuid", "uuid", "text"],
    returns: "jsonb",
  },
  { name: "drive_document_release", args: ["uuid", "uuid"], returns: "jsonb" },
  { name: "drive_document_obsolete", args: ["uuid", "text"], returns: "jsonb" },
  {
    name: "drive_document_review",
    args: ["uuid", "text", "text"],
    returns: "jsonb",
  },
  { name: "drive_documents", args: ["{id}", "jsonb"], returns: "jsonb" },
  { name: "notify_due_drive_reviews", args: [], returns: "integer" },
];

/** The numbering entity a document number comes from. */
const documentEntity = (own: BlockSqlContext): string =>
  own.resolved.entityNaming.rename("drive_document");

/**
 * The numbering entity of a document type: its own counter when the type sets a
 * `numberFormat`, the shared one otherwise.
 */
const typeEntity = (own: BlockSqlContext, type: string): string =>
  `${documentEntity(own)}_${type}`;

/** The defaults the other blocks get for controlled documents. */
export const DOCUMENT_CONTRIBUTES: BlockContributes = {
  numbering: (own) => {
    const control = driveControl(own.of("drive"));

    return control === undefined
      ? []
      : [
          {
            entity: documentEntity(own),
            entry: { period: "none", format: "DOC-{n:5}" },
          },
          ...Object.entries(control.numberFormats).map(([type, format]) => ({
            entity: typeEntity(own, type),
            entry: { period: "none", format },
          })),
        ];
  },
  relations: (own) => {
    const drive = own.of("drive");
    const type = driveSubjectType(drive);

    return driveControl(drive) === undefined
      ? []
      : [
          {
            kind: "variant_of",
            inverse: "variants",
            cardinality: "one",
            acyclic: true,
            types: { source: [type], target: [type] },
          },
        ];
  },
  acknowledgements: (own) => {
    const drive = own.of("drive");

    return driveControl(drive) === undefined
      ? []
      : [
          {
            subject: driveSubjectType(drive),
            versionColumn: drive.colName("nodes", "effectiveVersion"),
          },
        ];
  },
  approvals: (own) => {
    const drive = own.of("drive");

    return driveControl(drive) === undefined
      ? []
      : [
          {
            subject: driveSubjectType(drive),
            access: "declared",
            approve: (request) =>
              `perform ${own.fn("drive_document_decided")}(${request.id}, true);`,
            reject: (request) =>
              `perform ${own.fn("drive_document_decided")}(${request.id}, false);`,
          },
        ];
  },
  "state-machine": (own) => {
    const drive = own.of("drive");

    if (driveControl(drive) === undefined) {
      return [];
    }

    const { schema, name } = drive.tableName("nodes");

    const column = (key: string): string => drive.colName("nodes", key);

    return [
      {
        name: driveSubjectType(drive),
        optional: true,
        entry: {
          table: `${schema}.${name}`,
          column: column("documentStatus"),
          id: column("id"),
          idType: "uuid",
          tenant: column("tenant"),
          initial: "draft",
          transitions: {
            draft: ["in_review"],
            in_review: ["draft", "effective"],
            effective: ["obsolete"],
          },
          requiresApproval: { in_review: ["effective"] },
        },
      },
    ];
  },
};

/** The document columns drive-tables adds to a drive_nodes table it owns. */
export function documentColumnsSql(kit: DriveKit): string {
  const { ctx, T, n } = kit;

  if (driveControl(ctx) === undefined) {
    return "";
  }

  const index = (suffix: string): string =>
    sqlIdent(`${ctx.tableName("nodes").name}_${suffix}`);

  const add = (column: string, type: string): string =>
    `alter table ${T} add column if not exists ${n(column)} ${type};\n`;

  return `${add("documentNumber", `text check (length(${n("documentNumber")}) between 1 and 100)`)}${add("documentType", `text check (length(${n("documentType")}) between 1 and 63)`)}${add("documentStatus", `text check (${n("documentStatus")} in ('draft', 'in_review', 'effective', 'obsolete'))`)}${add("documentOwner", "uuid")}${add("effectiveVersion", "uuid")}${add("effectiveFrom", "timestamptz")}${add("reviewIntervalMonths", `integer check (${n("reviewIntervalMonths")} between 1 and 120)`)}${add("nextReviewOn", "date")}${add("reviewNotifiedFor", "date")}${ensureCheck(T, "bsb_drive_nodes_document_file", `${n("documentStatus")} is null or ${n("kind")} = 'file'`)}
create unique index if not exists ${index("document_number_idx")} on ${T} (${n("tenant")}, ${n("documentNumber")}) where ${n("documentNumber")} is not null;
create index if not exists ${index("document_owner_idx")} on ${T} (${n("documentOwner")}) where ${n("documentOwner")} is not null;
create index if not exists ${index("effective_version_idx")} on ${T} (${n("effectiveVersion")}) where ${n("effectiveVersion")} is not null;
create index if not exists ${index("next_review_idx")} on ${T} (${n("nextReviewOn")}) where ${n("documentStatus")} = 'effective';
`;
}

/** The attachment id of a node row's effective version, as uuid. */
const effectiveAttachment = (kit: DriveKit, row: string): string => {
  const VT = kit.versions?.table("versions") ?? "";

  return `(select (r.${kit.v("content")} ->> 'attachmentId')::uuid from ${VT} r where r.${kit.v("id")} = ${row}.${kit.n("effectiveVersion")})`;
};

/** The `document` key drive_node_json adds for a controlled file. */
export function documentJson(kit: DriveKit): string {
  const { ctx, n, v, canWrite } = kit;

  if (driveControl(ctx) === undefined || kit.versions === undefined) {
    return "";
  }

  const VT = kit.versions.table("versions");
  const col = (key: string): string => `($1).${n(key)}`;

  return `, 'document', case when ${col("documentStatus")} is null then null else jsonb_build_object('number', ${col("documentNumber")}, 'type', ${col("documentType")}, 'status', ${col("documentStatus")}, 'ownerId', ${col("documentOwner")}, 'effectiveVersionId', ${col("effectiveVersion")}, 'effectiveVersion', (select r.${v("number")} from ${VT} r where r.${v("id")} = ${col("effectiveVersion")}), 'effectiveAttachmentId', ${effectiveAttachment(kit, "($1)")}, 'effectiveFrom', ${col("effectiveFrom")}, 'reviewIntervalMonths', ${col("reviewIntervalMonths")}, 'nextReviewOn', ${col("nextReviewOn")}, 'reviewDue', coalesce(${col("documentStatus")} = 'effective' and ${col("nextReviewOn")} <= current_date, false), 'effectiveOnly', not ${canWrite(col("id"))}) end`;
}

/**
 * The clause drive_object_allowed adds for a stored object of a node: a
 * controlled document's reader below the write role reaches only the effective
 * version's bytes.
 */
export function documentGate(
  kit: DriveKit,
  node: string,
  attachment: string,
): string {
  return driveControl(kit.ctx) === undefined
    ? ""
    : ` and ${kit.fn("drive_document_readable")}(${node}, ${attachment})`;
}

/**
 * What drive-files renders before its functions: the effective version's
 * foreign key and drive_document_readable, which drive_object_allowed calls.
 */
export function documentPreludeSql(kit: DriveKit): string {
  const { ctx, T, n, fn, canWrite, versions, v } = kit;

  if (driveControl(ctx) === undefined || versions === undefined) {
    return "";
  }

  const key = ctx.owns("nodes")
    ? `alter table ${T} drop constraint if exists bsb_drive_nodes_effective_version;
alter table ${T} add constraint bsb_drive_nodes_effective_version foreign key (${n("effectiveVersion")}) references ${versions.table("versions")} (${v("id")}) on delete set null;
`
    : "";

  return `${key}
-- Whether the caller reaches attachment, stored bytes of node: always for a
-- file outside document control and for the write role; otherwise only the
-- effective version's.
create or replace function ${fn("drive_document_readable")}(node uuid, attachment uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select x.${n("documentStatus")} is null or ${canWrite(`x.${n("id")}`)}
      or coalesce(drive_document_readable.attachment = ${effectiveAttachment(kit, "x")}, false)
    from ${T} x where x.${n("id")} = drive_document_readable.node
  ), true)
$$;
revoke execute on function ${fn("drive_document_readable")}(uuid, uuid) from public, anon, authenticated;
`;
}

/** The controlled document functions of drive-files. */
export function driveDocumentsSql(kit: DriveKit): string {
  const control = driveControl(kit.ctx, kit.own);
  const { versions, A } = kit;

  if (control === undefined) {
    return "";
  }

  if (versions === undefined || A === undefined) {
    throw new TypeError(
      "blocks.drive.options.control needs files with attachments and versions",
    );
  }

  return `${saveSql(kit, control)}${submitSql(kit)}${releaseSql(kit, control)}${decidedSql(kit)}${obsoleteSql(kit, control)}${reviewSql(kit, control)}${registerSql(kit)}${dueSql(kit)}`;
}

/** The common opening: the node, locked, readable and a file. */
function loadNode(kit: DriveKit, fnName: string, what: string): string {
  const { T, n, canRead, notFound, live } = kit;

  return `select * into v_node from ${T} x where x.${n("id")} = ${fnName}.node${live("x")} for update;
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if v_node.${n("kind")} <> 'file' then
    ${fail("DRIVE_NOT_A_FILE", `only a file can be ${what}`, "22023")}
  end if;`;
}

const statusInvalid = (message: string): string =>
  fail("DRIVE_DOCUMENT_STATUS_INVALID", message, "22023");

const nextReview = (kit: DriveKit, control: DriveControl): string =>
  `(current_date + make_interval(months => coalesce(v_node.${kit.n("reviewIntervalMonths")}, ${String(control.reviewMonths)})))::date`;

function transitionTo(kit: DriveKit, status: string, reason: string): string {
  const machine = kit.own.of("state-machine");

  return `perform ${machine.fn("transition")}(${kit.typeLit}, v_node.${kit.n("id")}::text, ${sqlString(status)}, ${reason});`;
}

function saveSql(kit: DriveKit, control: DriveControl): string {
  const { own, T, n, fn, canWrite, forbidden, withRole, touch, record } = kit;
  const { tenant, m } = kit;
  const entity = documentEntity(own);
  const tenantSql = `v_node.${n("tenant")}`;

  const formatOf = (name: string): string => {
    const format = sequenceFormatOf(own, name, tenantSql)?.format;

    if (format === undefined) {
      throw new TypeError(
        `blocks.numbering.options.entities.${name} needs a format for document numbers`,
      );
    }

    return format;
  };

  const typed = Object.keys(control.numberFormats);

  const chosen =
    typed.length === 0
      ? `v_entity := ${sqlString(entity)};
    v_format := ${formatOf(entity)};`
      : `case drive_document_save.document_type
${typed
  .map(
    (type) =>
      `      when ${sqlString(type)} then
        v_entity := ${sqlString(typeEntity(own, type))};
        v_format := ${formatOf(typeEntity(own, type))};`,
  )
  .join("\n")}
      else
        v_entity := ${sqlString(entity)};
        v_format := ${formatOf(entity)};
    end case;`;

  const types = `array[${control.types.map(sqlString).join(", ")}]::text[]`;

  return `
-- Puts a file under document control, or changes its type, owner or review
-- interval: a new document gets the next number and starts as a draft.
create or replace function ${fn("drive_document_save")}(node uuid, document_type text, owner_id uuid default null, review_interval_months integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_seq bigint;
  v_number text;
  v_entity text;
  v_format text;
begin
  ${READ_ONLY_GUARD}
  ${loadNode(kit, "drive_document_save", "a controlled document")}
  if not (${SERVICE_CALLER} or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("control this document")}
  end if;
  ${lockGuard(kit, "v_node")}
  if drive_document_save.document_type is null or not (drive_document_save.document_type = any (${types})) then
    ${fail("DRIVE_DOCUMENT_TYPE_UNKNOWN", "that document type is not in options.control.types", "22023")}
  end if;
  if v_node.${n("documentStatus")} = 'obsolete' then
    ${statusInvalid("an obsolete document can't change")}
  end if;
  if drive_document_save.owner_id is not null and not exists (
    select 1 from ${tenant.table("memberships")} mu
    where mu.${m("tenant")} = v_node.${n("tenant")} and mu.${m("user")} = drive_document_save.owner_id${activeMembership(kit.ctx, "mu")}
  ) then
    ${fail("DRIVE_DOCUMENT_OWNER_INVALID", "the owner must be a member of the organization", "22023")}
  end if;
  v_number := v_node.${n("documentNumber")};
  if v_number is null then
    ${chosen}
    ${withFixedNumber(
      own,
      "document",
      `v_node.${n("tenant")}`,
      { seq: "v_seq", text: "v_number" },
      `v_seq := ${own.of("numbering").fn("next_number")}(v_node.${n("tenant")}, v_entity, now());
    v_number := better_supabase.format_assigned_number(v_format, v_seq, now());`,
      { at: "now()", scope: "''", registered: true, entitySql: "v_entity" },
    )}
  end if;
  update ${T} x set ${n("documentNumber")} = v_number,
    ${n("documentType")} = drive_document_save.document_type,
    ${n("documentOwner")} = coalesce(drive_document_save.owner_id, x.${n("documentOwner")}, auth.uid()),
    ${n("reviewIntervalMonths")} = coalesce(drive_document_save.review_interval_months, x.${n("reviewIntervalMonths")})${touch}
  where x.${n("id")} = v_node.${n("id")}
  returning * into v_node;
  if v_node.${n("documentStatus")} is null then
    ${transitionTo(kit, "draft", "null")}
    select * into v_node from ${T} x where x.${n("id")} = v_node.${n("id")};
  end if;
  ${record("drive_node.document_saved", "v_node", `, 'documentNumber', v_node.${n("documentNumber")}, 'documentType', v_node.${n("documentType")}, 'ownerId', v_node.${n("documentOwner")}`, kit.dataAudit("v_node", "document saved"))}
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_document_save")}(uuid, text, uuid, integer)`)}
`;
}

function submitSql(kit: DriveKit): string {
  const { own, T, n, fn, A, a, canWrite, forbidden, withRole, record } = kit;
  const { typeLit, versions, v } = kit;
  const approvals = own.of("approvals");
  const c = (column: string): string => approvals.col("requests", column);
  const VT = versions?.table("versions") ?? "";

  return `
-- Sends a draft or an effective document's attachment (the current one by
-- default) for release through an approval request with action release. A
-- draft moves to in_review; an effective document stays effective, so its
-- readers keep the released version until the new one is approved.
create or replace function ${fn("drive_document_submit")}(node uuid, attachment uuid default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_file ${A}%rowtype;
  v_revision integer;
  v_request jsonb;
begin
  ${READ_ONLY_GUARD}
  ${loadNode(kit, "drive_document_submit", "released")}
  if not (${SERVICE_CALLER} or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("submit this document")}
  end if;
  ${lockGuard(kit, "v_node")}
  if v_node.${n("documentStatus")} is null then
    ${statusInvalid("save the file as a controlled document first")}
  end if;
  if not (v_node.${n("documentStatus")} = 'draft' or (v_node.${n("documentStatus")} in ('in_review', 'effective') and not exists (
    select 1 from ${approvals.table("requests")} q
    where q.${c("subjectType")} = ${typeLit} and q.${c("subjectId")} = v_node.${n("id")}::text
      and q.${c("action")} = ${RELEASE} and q.${c("status")} = 'pending'
  ))) then
    ${statusInvalid("only a draft, or an effective document without a pending release, can be submitted")}
  end if;
  select * into v_file from ${A} f
  where f.${a("id")} = coalesce(drive_document_submit.attachment, v_node.${n("attachment")})
    and f.${a("subjectType")} = ${typeLit} and f.${a("subjectId")} = v_node.${n("id")}::text
    and f.${a("uploadedAt")} is not null;
  if not found then
    ${fail("DRIVE_ATTACHMENT_NOT_FOUND", "that version of the file was not found", "P0002")}
  end if;
  select r.${v("number")} into v_revision from ${VT} r
  where r.${v("subjectType")} = ${typeLit} and r.${v("subjectId")} = v_node.${n("id")}::text
    and r.${v("content")} ->> 'attachmentId' = v_file.${a("id")}::text
  order by r.${v("number")} limit 1;
  if v_node.${n("documentStatus")} = 'draft' then
    ${transitionTo(kit, "in_review", "drive_document_submit.reason")}
  end if;
  v_request := ${approvals.fn("request_approval")}(v_node.${n("tenant")}, ${typeLit}, v_node.${n("id")}::text, ${RELEASE},
    drive_document_submit.reason, jsonb_build_object('attachmentId', v_file.${a("id")}, 'revision', v_revision, 'name', v_file.${a("name")}));
  select * into v_node from ${T} x where x.${n("id")} = v_node.${n("id")};
  ${record("drive_node.submitted", "v_node", `, 'documentNumber', v_node.${n("documentNumber")}, 'attachmentId', v_file.${a("id")}, 'requestId', v_request ->> 'id'`, kit.dataAudit("v_node", "document submitted"))}
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_document_submit")}(uuid, uuid, text)`)}
`;
}

function releaseSql(kit: DriveKit, control: DriveControl): string {
  const { own, T, n, fn, A, a, withRole, record, typeLit, v } = kit;
  const VT = kit.versions?.table("versions") ?? "";
  const versions = kit.versions?.fn("version_insert") ?? "";
  const approvals = own.of("approvals");
  const c = (column: string): string => approvals.col("requests", column);

  return `
-- Makes attachment the document's effective version: its version is frozen
-- and labelled effective, the previous one is labelled superseded, and the
-- next review falls review_interval_months later (options.control.reviewMonths
-- by default). The service role calls it, and so does an approved release
-- request through drive_document_decided.
create or replace function ${fn("drive_document_release")}(node uuid, attachment uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_file ${A}%rowtype;
  v_version uuid;
  v_inserted jsonb;
begin
  if not (${SERVICE_CALLER} or exists (
    select 1 from ${approvals.table("requests")} q
    where q.${c("id")}::text = nullif(current_setting('better_supabase.approval', true), '')
      and q.${c("status")} = 'approved' and q.${c("action")} = ${RELEASE}
      and q.${c("subjectType")} = ${typeLit} and q.${c("subjectId")} = drive_document_release.node::text
  )) then
    ${fail("DRIVE_FORBIDDEN", "only an approved release request releases a document")}
  end if;
  ${loadNode(kit, "drive_document_release", "released")}
  if v_node.${n("documentStatus")} is null or v_node.${n("documentStatus")} not in ('in_review', 'effective') then
    ${statusInvalid("only a document in review or an effective one can be released")}
  end if;
  select * into v_file from ${A} f
  where f.${a("id")} = drive_document_release.attachment
    and f.${a("subjectType")} = ${typeLit} and f.${a("subjectId")} = v_node.${n("id")}::text
    and f.${a("uploadedAt")} is not null;
  if not found then
    ${fail("DRIVE_ATTACHMENT_NOT_FOUND", "that version of the file was not found", "P0002")}
  end if;
  select r.${v("id")} into v_version from ${VT} r
  where r.${v("subjectType")} = ${typeLit} and r.${v("subjectId")} = v_node.${n("id")}::text
    and r.${v("content")} ->> 'attachmentId' = v_file.${a("id")}::text
  order by r.${v("number")} desc limit 1;
  if v_version is null then
    v_inserted := ${versions}(v_node.${n("tenant")}, ${typeLit}, v_node.${n("id")}::text,
      jsonb_build_object('attachmentId', v_file.${a("id")}, 'name', v_file.${a("name")}, 'mimeType', v_file.${a("mimeType")}, 'size', v_file.${a("size")}),
      v_file.${a("bucket")} || '/' || v_file.${a("path")}, 'effective', 'manual', true, auth.uid());
    v_version := (v_inserted ->> 'id')::uuid;
  else
    update ${VT} r set ${v("label")} = 'effective', ${v("frozen")} = true where r.${v("id")} = v_version;
  end if;
  update ${VT} r set ${v("label")} = 'superseded'
  where r.${v("id")} = v_node.${n("effectiveVersion")} and r.${v("id")} <> v_version;
  update ${T} x set ${n("effectiveVersion")} = v_version, ${n("effectiveFrom")} = now(),
    ${n("nextReviewOn")} = ${nextReview(kit, control)}, ${n("reviewNotifiedFor")} = null
  where x.${n("id")} = v_node.${n("id")};
  if v_node.${n("documentStatus")} = 'in_review' then
    ${transitionTo(kit, "effective", "'released'")}
  end if;
  select * into v_node from ${T} x where x.${n("id")} = v_node.${n("id")};
  ${record("drive_node.released", "v_node", `, 'documentNumber', v_node.${n("documentNumber")}, 'versionId', v_version, 'attachmentId', v_file.${a("id")}`, kit.dataAudit("v_node", "document released"))}
  return ${withRole("v_node")};
end;
$$;
${serviceGrant(`${fn("drive_document_release")}(uuid, uuid)`)}
`;
}

function decidedSql(kit: DriveKit): string {
  const { own, T, n, fn, typeLit } = kit;
  const approvals = own.of("approvals");
  const c = (column: string): string => approvals.col("requests", column);

  const payload = approvals.has("requests", "payload")
    ? `(v_req.${c("payload")} ->> 'attachmentId')::uuid`
    : "null::uuid";

  return `
-- Runs when approvals decides a release request: an approval releases the
-- attachment it names, a rejection sends a document in review back to draft
-- and leaves an effective one as it is. Other actions on the file pass.
create or replace function ${fn("drive_document_decided")}(request uuid, approved boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req ${approvals.table("requests")}%rowtype;
  v_node ${T}%rowtype;
begin
  select * into v_req from ${approvals.table("requests")} q where q.${c("id")} = drive_document_decided.request;
  if not found or v_req.${c("action")} <> ${RELEASE} or v_req.${c("subjectType")} <> ${typeLit} then
    return;
  end if;
  select * into v_node from ${T} x where x.${n("id")}::text = v_req.${c("subjectId")} for update;
  if not found or v_node.${n("documentStatus")} is null or v_node.${n("documentStatus")} not in ('in_review', 'effective') then
    return;
  end if;
  if drive_document_decided.approved then
    perform set_config('better_supabase.approval', v_req.${c("id")}::text, true);
    perform ${fn("drive_document_release")}(v_node.${n("id")}, coalesce(${payload}, v_node.${n("attachment")}));
    perform set_config('better_supabase.approval', '', true);
  elsif v_node.${n("documentStatus")} = 'in_review' then
    ${transitionTo(kit, "draft", "'rejected'")}
  end if;
end;
$$;
revoke execute on function ${fn("drive_document_decided")}(uuid, boolean) from public, anon, authenticated;
`;
}

function obsoleteSql(kit: DriveKit, control: DriveControl): string {
  const { T, n, fn, roles, forbidden, withRole, record } = kit;
  const role = control.releaseRole ?? roles.share;

  if (!roles.all.includes(role)) {
    throw new TypeError(
      "blocks.drive.options.control.releaseRole must be one of options.roles",
    );
  }

  return `
-- Withdraws an effective document: it stays readable as obsolete and can't
-- be submitted again. Needs options.control.releaseRole on the file.
create or replace function ${fn("drive_document_obsolete")}(node uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  ${READ_ONLY_GUARD}
  ${loadNode(kit, "drive_document_obsolete", "obsoleted")}
  if not (${SERVICE_CALLER} or ${fn("drive_can")}(v_node.${n("id")}, ${sqlString(role)})) then
    ${forbidden("withdraw this document")}
  end if;
  ${lockGuard(kit, "v_node")}
  if v_node.${n("documentStatus")} is distinct from 'effective' then
    ${statusInvalid("only an effective document can be made obsolete")}
  end if;
  ${transitionTo(kit, "obsolete", "drive_document_obsolete.reason")}
  select * into v_node from ${T} x where x.${n("id")} = v_node.${n("id")};
  ${record("drive_node.obsoleted", "v_node", `, 'documentNumber', v_node.${n("documentNumber")}, 'reason', drive_document_obsolete.reason`, kit.dataAudit("v_node", "document made obsolete"))}
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_document_obsolete")}(uuid, text)`)}
`;
}

function reviewSql(kit: DriveKit, control: DriveControl): string {
  const { T, n, fn, canWrite, forbidden, withRole, record } = kit;

  return `
-- Records a periodic review of an effective document by its owner or a
-- writer. unchanged moves the next review on by the interval; revise leaves
-- the document effective until a new version is submitted and released.
create or replace function ${fn("drive_document_review")}(node uuid, outcome text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  ${READ_ONLY_GUARD}
  ${loadNode(kit, "drive_document_review", "reviewed")}
  if not (${SERVICE_CALLER} or v_node.${n("documentOwner")} = auth.uid() or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("review this document")}
  end if;
  if drive_document_review.outcome is null or drive_document_review.outcome not in ('unchanged', 'revise') then
    ${fail("DRIVE_DOCUMENT_REVIEW_INVALID", "outcome must be unchanged or revise", "22023")}
  end if;
  if v_node.${n("documentStatus")} is distinct from 'effective' then
    ${statusInvalid("only an effective document is reviewed")}
  end if;
  if drive_document_review.outcome = 'unchanged' then
    update ${T} x set ${n("nextReviewOn")} = ${nextReview(kit, control)}, ${n("reviewNotifiedFor")} = null
    where x.${n("id")} = v_node.${n("id")}
    returning * into v_node;
  end if;
  ${record("drive_node.reviewed", "v_node", `, 'documentNumber', v_node.${n("documentNumber")}, 'outcome', drive_document_review.outcome, 'note', drive_document_review.note, 'nextReviewOn', v_node.${n("nextReviewOn")}`, kit.dataAudit("v_node", "document reviewed"))}
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_document_review")}(uuid, text, text)`)}
`;
}

function registerSql(kit: DriveKit): string {
  const { ctx, T, n, fn, canRead, withRole, live } = kit;

  const filter = (key: string): string =>
    `drive_documents.filters ->> '${key}'`;

  return `
-- The document register of an organization: its controlled files the caller
-- reads, by number. filters takes type, status, ownerId, reviewDue (true for
-- effective documents whose review date has come) and search (number or name).
create or replace function ${fn("drive_documents")}(tenant ${ctx.idType}, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if jsonb_typeof(coalesce(drive_documents.filters, '{}'::jsonb)) <> 'object' then
    ${fail("DRIVE_DOCUMENT_FILTER_INVALID", "filters must be an object", "22023")}
  end if;
  return coalesce((
    select jsonb_agg(${withRole("x")} order by x.${n("documentNumber")})
    from ${T} x
    where x.${n("tenant")} = drive_documents.tenant and x.${n("documentStatus")} is not null${live("x")}
      and (${SERVICE_CALLER} or ${canRead(`x.${n("id")}`)})
      and (${filter("type")} is null or x.${n("documentType")} = ${filter("type")})
      and (${filter("status")} is null or x.${n("documentStatus")} = ${filter("status")})
      and (${filter("ownerId")} is null or x.${n("documentOwner")}::text = ${filter("ownerId")})
      and (coalesce((${filter("reviewDue")})::boolean, false) = false
        or (x.${n("documentStatus")} = 'effective' and x.${n("nextReviewOn")} <= current_date))
      and (coalesce(${filter("search")}, '') = ''
        or x.${n("documentNumber")} ilike '%' || (${filter("search")}) || '%'
        or x.${n("name")} ilike '%' || (${filter("search")}) || '%')
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("drive_documents")}(${ctx.idType}, jsonb)`)}
`;
}

function dueSql(kit: DriveKit): string {
  const { own, T, n, fn, typeLit, record } = kit;

  const notify = own.installed("notifications")
    ? `if v_node.${n("documentOwner")} is not null then
      ${own.notify(
        `jsonb_build_object(
        'type', 'drive.document_review_due',
        'tenant', v_node.${n("tenant")},
        'actor', null,
        'subject_type', ${typeLit},
        'subject_id', v_node.${n("id")}::text,
        'summary', v_node.${n("documentNumber")} || ' ' || v_node.${n("name")},
        'recipients', to_jsonb(array[v_node.${n("documentOwner")}]),
        'key', 'drive.document_review_due:' || v_node.${n("id")}::text || ':' || v_node.${n("nextReviewOn")}::text,
        'data', jsonb_build_object('nodeId', v_node.${n("id")}, 'documentNumber', v_node.${n("documentNumber")}, 'nextReviewOn', v_node.${n("nextReviewOn")})
      )`,
        { indent: "      " },
      )}
    end if;`
    : "";

  return `
-- Reports each effective document whose review date has come once per date:
-- a drive_node.review_requested event and, with notifications, a notification
-- to its owner. Run it daily from a job.
create or replace function ${fn("notify_due_drive_reviews")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_node ${T}%rowtype;
  v_count integer := 0;${notify === "" ? "" : "\n  v_claims text;"}
begin
  for v_node in
    select * from ${T} x
    where x.${n("documentStatus")} = 'effective' and x.${n("nextReviewOn")} <= current_date
      and x.${n("reviewNotifiedFor")} is distinct from x.${n("nextReviewOn")}${kit.live("x")}
    for update skip locked
  loop
    ${record("drive_node.review_requested", "v_node", `, 'documentNumber', v_node.${n("documentNumber")}, 'ownerId', v_node.${n("documentOwner")}, 'nextReviewOn', v_node.${n("nextReviewOn")}`, false)}
    ${notify}
    update ${T} x set ${n("reviewNotifiedFor")} = v_node.${n("nextReviewOn")} where x.${n("id")} = v_node.${n("id")};
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("notify_due_drive_reviews")}()`)}
`;
}
