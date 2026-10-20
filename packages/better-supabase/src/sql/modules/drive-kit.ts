import type { DriveEvents } from "../../blocks/drive/events.ts";
import type {
  ModuleAudit,
  ModuleContext,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { rankAfter } from "../rank-sql.ts";
import { activeMembership, columnsObject, fail } from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";
import { trashTypes } from "./trash.ts";

const SUBJECT_TYPE = /^[a-z][a-z0-9_]{0,62}$/;
const ROLE = /^[a-z][a-z0-9_]{0,30}$/;
export const CONFLICTS = ["fail", "rename", "replace"] as const;

/**
 * The read-only session check for functions whose only writes happen in the
 * internal helpers they call, which the write guard can't see.
 */
export const READ_ONLY_GUARD =
  "perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();";

export const UUID_TEXT =
  "'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'";

const PATH_SEGMENT = "drive-nodes";

const SUBJECT = ["organizationId", "subjectType", "subjectId"] as const;

const EVENTS: ModuleEvents<DriveEvents> = {
  "drive.node_created": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "kind", "name", "parentId"],
  },
  "drive.node_renamed": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "name", "previousName"],
  },
  "drive.node_moved": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "parentId", "previousParentId"],
  },
  "drive.node_shared": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "principalType", "principalId", "role"],
  },
  "drive.node_unshared": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "principalType", "principalId"],
  },
};

export const FILE_EVENTS: ModuleEvents<DriveEvents> = {
  "drive.node_purged": {
    subject: PATH_SEGMENT,
    payload: [...SUBJECT, "objects"],
  },
};

export const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_drive_node_create",
    "after_drive_node_create",
    "before_drive_node_move",
    "after_drive_node_move",
    "before_drive_node_rename",
    "after_drive_node_rename",
    "before_drive_node_share",
    "after_drive_node_share",
  ],
  options: [
    "roles",
    "writeRole",
    "shareRole",
    "memberRole",
    "subjectType",
    "conflict",
    "extraColumns",
  ],
  tables: {
    nodes: {
      name: "drive_nodes",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        parent: "parent_id",
        kind: "kind",
        name: "name",
        attachment: "attachment_id",
        path: "path",
        rank: "rank",
        deletedAt: "deleted_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "attachment",
        "path",
        "rank",
        "deletedAt",
        "createdBy",
        "updatedAt",
      ],
    },
    grants: {
      name: "drive_grants",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        node: "node_id",
        principalType: "principal_type",
        principalId: "principal_id",
        user: "user_id",
        team: "team_id",
        role: "role",
        expiresAt: "expires_at",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: [
        "principalType",
        "principalId",
        "user",
        "team",
        "expiresAt",
        "createdBy",
      ],
    },
  },
};

export interface DriveRoles {
  readonly all: readonly string[];
  readonly read: string;
  readonly write: string;
  readonly share: string;
  readonly top: string;
  readonly member: string | undefined;
}

/** `options.roles` (lowest first) and the roles each action needs. */
function driveRoles(ctx: ModuleContext): DriveRoles {
  const where = "blocks.drive.options";
  const all = ctx.list("roles", ["viewer", "editor", "owner"]);

  if (
    all.length === 0 ||
    new Set(all).size !== all.length ||
    !all.every((role) => ROLE.test(role))
  ) {
    throw new TypeError(
      `${where}.roles must list distinct lowercase role names, lowest first`,
    );
  }

  const pick = (name: string, fallback: string): string => {
    const role = ctx.text(name, fallback);

    if (!all.includes(role)) {
      throw new TypeError(`${where}.${name} must be one of options.roles`);
    }

    return role;
  };

  const top = all.at(-1) ?? "owner";
  const member = ctx.option("memberRole");

  if (
    member !== undefined &&
    (typeof member !== "string" || !all.includes(member))
  ) {
    throw new TypeError(`${where}.memberRole must be one of options.roles`);
  }

  return {
    all,
    read: all[0] ?? "viewer",
    write: pick("writeRole", all.includes("editor") ? "editor" : top),
    share: pick("shareRole", top),
    top,
    member,
  };
}

/** `options.subjectType`: the subject type of a node, `drive_node` by default. */
export function driveSubjectType(ctx: ModuleContext): string {
  const type = ctx.text("subjectType", "drive_node");

  if (!SUBJECT_TYPE.test(type)) {
    throw new TypeError(
      "blocks.drive.options.subjectType must be lowercase letters, digits and underscores",
    );
  }

  return type;
}

function conflictDefault(ctx: ModuleContext): string {
  const conflict = ctx.text("conflict", "fail");

  if (!CONFLICTS.some((value) => value === conflict)) {
    throw new TypeError(
      `blocks.drive.options.conflict must be one of ${CONFLICTS.join(", ")}`,
    );
  }

  return conflict;
}

const usable = (ctx: ModuleContext, name: string): ModuleContext | undefined =>
  ctx.installed(name) && ctx.of(name).mode !== "custom"
    ? ctx.of(name)
    : undefined;

/** What both drive modules render with: tables, options and SQL helpers. */
export interface DriveKit {
  readonly ctx: ModuleContext;
  readonly own: ModuleContext;
  readonly T: string;
  readonly G: string;
  readonly n: (value: string) => string;
  readonly g: (value: string) => string;
  readonly fn: (value: string) => string;
  readonly read: string;
  readonly create: string;
  readonly manage: string;
  readonly roles: DriveRoles;
  readonly type: string;
  readonly typeLit: string;
  readonly conflict: string;
  readonly extras: ReturnType<ModuleContext["extraColumns"]>;
  readonly has: (column: string) => boolean;
  readonly pathMode: boolean;
  readonly ranked: boolean;
  readonly binColumn: boolean;
  readonly typed: boolean;
  readonly teamColumn: boolean;
  readonly expiring: boolean;
  readonly attachments: ModuleContext | undefined;
  readonly A: string | undefined;
  readonly a: (value: string) => string;
  readonly versions: ModuleContext | undefined;
  readonly v: (value: string) => string;
  readonly trash: ModuleContext | undefined;
  readonly ti: (value: string) => string;
  readonly shareLinks: ModuleContext | undefined;
  readonly state: ModuleContext | undefined;
  readonly st: (value: string) => string;
  readonly teams: ModuleContext | undefined;
  readonly tenant: ModuleContext;
  readonly m: (value: string) => string;
  readonly rolesArray: string;
  readonly rank: (value: string) => string;
  readonly live: (value: string) => string;
  readonly canRead: (value: string) => string;
  readonly canWrite: (value: string) => string;
  readonly canShare: (value: string) => string;
  readonly notFound: string;
  readonly forbidden: (value: string) => string;
  readonly record: (
    event: string,
    row: string,
    extra: string,
    audit: ModuleAudit | false,
  ) => string;
  readonly dataAudit: (row: string, summary: string) => ModuleAudit;
  readonly accessAudit: (row: string, summary: string) => ModuleAudit;
  readonly principalMatch: (
    grant: string,
    uid: string,
    tenantId: string,
  ) => string;
  readonly grantLive: (value: string) => string;
  readonly principalType: (value: string) => string;
  readonly principalId: (value: string) => string;
  readonly fileJson: string;
  readonly nodeJson: (value: string) => string;
  readonly json: (value: string) => string;
  readonly withRole: (value: string) => string;
  readonly orderBy: (value: string) => string;
  readonly touch: string;
  readonly insertColumns: readonly string[];
  readonly insertValues: readonly string[];
  readonly directGrant: (node: string, role: string, uid: string) => string;
  readonly siblings: (
    alias: string,
    tenantId: string,
    parent: string,
  ) => string;
}

/** `ctx` is the drive module's context; `own` records the events of the module rendering. */
export function driveKit(ctx: ModuleContext, own: ModuleContext): DriveKit {
  const T = ctx.table("nodes");
  const G = ctx.table("grants");
  const n = (column: string): string => ctx.col("nodes", column);
  const g = (column: string): string => ctx.col("grants", column);
  const fn = (name: string): string => ctx.fn(name);
  const read = ctx.permission("read", OPERATIONS["drive.read"]);
  const create = ctx.permission("create", OPERATIONS["drive.create"]);
  const manage = ctx.permission("manage", OPERATIONS["drive.manage"]);
  const roles = driveRoles(ctx);
  const type = driveSubjectType(ctx);
  const typeLit = sqlString(type);
  const conflict = sqlString(conflictDefault(ctx));

  const extras = ctx.extraColumns("nodes", [
    "organizationId",
    "parentId",
    "attachmentId",
    "file",
    "fields",
    "role",
  ]);

  const has = (column: string): boolean => ctx.has("nodes", column);
  const pathMode = has("path");
  const ranked = has("rank");
  const binColumn = has("deletedAt");
  const typed = ctx.has("grants", "principalType");

  if (!typed && !ctx.has("grants", "user")) {
    throw new TypeError(
      "blocks.drive.columns.grants needs principalType and principalId, or user (and team)",
    );
  }

  const teamColumn = !typed && ctx.has("grants", "team");
  const expiring = ctx.has("grants", "expiresAt");

  const attachments = has("attachment")
    ? usable(ctx, "attachments")
    : undefined;

  const A = attachments?.table("attachments");

  const a = (column: string): string =>
    attachments === undefined ? column : attachments.col("attachments", column);

  const versions =
    attachments === undefined ? undefined : usable(ctx, "versions");

  const v = (column: string): string =>
    versions === undefined ? column : versions.col("versions", column);

  const trash =
    binColumn &&
    usable(ctx, "trash") !== undefined &&
    trashTypes(ctx.of("trash")).has(type)
      ? ctx.of("trash")
      : undefined;

  const ti = (column: string): string =>
    trash === undefined ? column : trash.col("items", column);

  const shareLinks = usable(ctx, "share-links");
  const state = shareLinks?.hasTable("state") ? shareLinks : undefined;

  const st = (column: string): string =>
    state === undefined ? column : state.col("state", column);

  const teams = usable(ctx, "teams");
  const tenant = ctx.of("tenant");
  const m = (column: string): string => tenant.col("memberships", column);

  const rolesArray = `array[${roles.all.map(sqlString).join(", ")}]::text[]`;

  const rank = (role: string): string =>
    `coalesce(array_position(${rolesArray}, ${role}), 0)`;

  const live = (row: string): string =>
    binColumn ? ` and ${row}.${n("deletedAt")} is null` : "";

  const canRead = (node: string): string =>
    `${fn("drive_can")}(${node}, ${sqlString(roles.read)})`;

  const canWrite = (node: string): string =>
    `${fn("drive_can")}(${node}, ${sqlString(roles.write)})`;

  const canShare = (node: string): string =>
    `${fn("drive_can")}(${node}, ${sqlString(roles.share)})`;

  const notFound = fail("DRIVE_NOT_FOUND", "drive item not found", "P0002");

  const forbidden = (what: string): string =>
    fail("DRIVE_FORBIDDEN", `not allowed to ${what}`);

  const record = (
    event: string,
    row: string,
    extra: string,
    audit: ModuleAudit | false,
  ): string =>
    own.record({
      type: event,
      payload: `jsonb_build_object('organizationId', ${row}.${n("tenant")}::text, 'subjectType', ${typeLit}, 'subjectId', ${row}.${n("id")}::text${extra})`,
      subject: `${sqlString(`${PATH_SEGMENT}/`)} || ${row}.${n("id")}::text`,
      tenant: `${row}.${n("tenant")}`,
      audit,
    });

  const dataAudit = (row: string, summary: string): ModuleAudit => ({
    category: "data",
    targetType: type,
    recordId: `${row}.${n("id")}::text`,
    targetLabel: `${row}.${n("name")}`,
    summary: sqlString(summary),
  });

  const accessAudit = (row: string, summary: string): ModuleAudit => ({
    category: "access",
    targetType: type,
    recordId: `${row}.${n("id")}::text`,
    targetLabel: `${row}.${n("name")}`,
    summary: sqlString(summary),
  });

  const principalMatch = (
    grant: string,
    uid: string,
    tenantId: string,
  ): string => {
    const teamMember = (team: string): string =>
      teams === undefined
        ? "false"
        : `exists (select 1 from ${teams.table("members")} tm where tm.${teams.col("members", "team")}::text = ${team}::text and tm.${teams.col("members", "user")} = ${uid})`;

    if (!typed) {
      return `(${grant}.${g("user")} = ${uid}${teamColumn ? ` or (${grant}.${g("team")} is not null and ${teamMember(`${grant}.${g("team")}`)})` : ""})`;
    }

    return `((${grant}.${g("principalType")} = 'user' and ${grant}.${g("principalId")} = ${uid}::text)
      or (${grant}.${g("principalType")} = 'team' and ${teamMember(`${grant}.${g("principalId")}`)})
      or (${grant}.${g("principalType")} = 'role' and exists (select 1 from ${tenant.table("memberships")} mr where mr.${m("tenant")} = ${tenantId} and mr.${m("user")} = ${uid} and mr.${m("role")}::text = ${grant}.${g("principalId")}${activeMembership(ctx, "mr")})))`;
  };

  const grantLive = (grant: string): string =>
    expiring
      ? ` and (${grant}.${g("expiresAt")} is null or ${grant}.${g("expiresAt")} > now())`
      : "";

  const principalType = (grant: string): string =>
    typed
      ? `${grant}.${g("principalType")}`
      : teamColumn
        ? `case when ${grant}.${g("user")} is not null then 'user' else 'team' end`
        : "'user'";

  const principalId = (grant: string): string =>
    typed
      ? `${grant}.${g("principalId")}`
      : teamColumn
        ? `coalesce(${grant}.${g("user")}::text, ${grant}.${g("team")}::text)`
        : `${grant}.${g("user")}::text`;

  const fileJson =
    A === undefined
      ? ""
      : `, 'attachmentId', ($1).${n("attachment")}, 'file', (select jsonb_build_object('mimeType', fa.${a("mimeType")}, 'size', fa.${a("size")}, 'status', fa.${a("status")}, 'uploadedAt', fa.${a("uploadedAt")}) from ${A} fa where fa.${a("id")} = ($1).${n("attachment")})`;

  const nodeJson = (file: string): string =>
    `jsonb_build_object('id', ($1).${n("id")}, 'organizationId', ($1).${n("tenant")}, 'parentId', ($1).${n("parent")}, 'kind', ($1).${n("kind")}, 'name', ($1).${n("name")}, 'rank', ${ranked ? `($1).${n("rank")}` : "null"}, 'createdBy', ${has("createdBy") ? `($1).${n("createdBy")}` : "null"}, 'createdAt', ($1).${n("createdAt")}, 'updatedAt', ${has("updatedAt") ? `($1).${n("updatedAt")}` : "null"}, 'deletedAt', ${binColumn ? `($1).${n("deletedAt")}` : "null"}${file}${
      extras.length === 0
        ? ""
        : `, 'fields', ${columnsObject(
            "($1)",
            extras.map((column) => column.name),
          )}`
    })`;

  const json = (row: string): string => `${fn("drive_node_json")}(${row})`;

  const withRole = (row: string): string =>
    `(${json(row)} || jsonb_build_object('role', ${fn("drive_role")}((${row}).${n("id")})))`;

  const orderBy = (alias: string): string =>
    `(${alias}.${n("kind")} = 'folder') desc${ranked ? `, ${alias}.${n("rank")}` : ""}, lower(${alias}.${n("name")}), ${alias}.${n("id")}`;

  const touch = has("updatedAt") ? `, ${n("updatedAt")} = now()` : "";

  const insertColumns = [
    n("tenant"),
    n("parent"),
    n("kind"),
    n("name"),
    ...(ranked ? [n("rank")] : []),
    ...(has("createdBy") ? [n("createdBy")] : []),
    ...extras.map((column) => column.ident),
  ];

  const insertValues = [
    "drive_insert_node.tenant",
    "drive_insert_node.parent",
    "drive_insert_node.kind",
    "v_name",
    ...(ranked ? [rankAfter("v_last")] : []),
    ...(has("createdBy") ? ["auth.uid()"] : []),
    ...extras.map(
      (column) =>
        `coalesce(v_fields.${column.ident}, v_parent.${column.ident})`,
    ),
  ];

  const directGrant = (node: string, role: string, uid: string): string =>
    typed
      ? `insert into ${G} (${g("tenant")}, ${g("node")}, ${g("principalType")}, ${g("principalId")}, ${g("role")})
    values (${node}.${n("tenant")}, ${node}.${n("id")}, 'user', ${uid}::text, ${role})
    on conflict (${g("node")}, ${g("principalType")}, ${g("principalId")}) do update set ${g("role")} = excluded.${g("role")};`
      : `delete from ${G} dg where dg.${g("node")} = ${node}.${n("id")} and dg.${g("user")} = ${uid};
    insert into ${G} (${g("tenant")}, ${g("node")}, ${g("user")}, ${g("role")})
    values (${node}.${n("tenant")}, ${node}.${n("id")}, ${uid}, ${role});`;

  const siblings = (alias: string, tenantId: string, parent: string): string =>
    `${alias}.${n("tenant")} = ${tenantId} and ${alias}.${n("parent")} is not distinct from ${parent}${live(alias)}`;

  return {
    ctx,
    own,
    T,
    G,
    n,
    g,
    fn,
    read,
    create,
    manage,
    roles,
    type,
    typeLit,
    conflict,
    extras,
    has,
    pathMode,
    ranked,
    binColumn,
    typed,
    teamColumn,
    expiring,
    attachments,
    A,
    a,
    versions,
    v,
    trash,
    ti,
    shareLinks,
    state,
    st,
    teams,
    tenant,
    m,
    rolesArray,
    rank,
    live,
    canRead,
    canWrite,
    canShare,
    notFound,
    forbidden,
    record,
    dataAudit,
    accessAudit,
    principalMatch,
    grantLive,
    principalType,
    principalId,
    fileJson,
    nodeJson,
    json,
    withRole,
    orderBy,
    touch,
    insertColumns,
    insertValues,
    directGrant,
    siblings,
  };
}
