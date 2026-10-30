import type { DriveKit } from "./drive-kit.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { UUID_TEXT } from "./drive-kit.ts";
import { liveShareLink } from "./share-links.ts";

/** The rate-limit scope of uploads through one file request link. */
const REQUEST_SCOPE = "drive_link_upload";
const REQUEST_UPLOADS = 20;
const REQUEST_PERIOD = "1 hour";

/**
 * Share links on drive nodes: what a link opens, and file requests (upload
 * links on a folder). Renders nothing without share-links.
 */
export function driveLinksSql(kit: DriveKit): string {
  const {
    own,
    T,
    n,
    fn,
    driveColumn,
    readOnly,
    typeLit,
    attachments,
    A,
    a,
    shareLinks,
    live,
    canRead,
    notFound,
    roles,
    json,
    orderBy,
    previewColumn,
  } = kit;

  if (shareLinks === undefined) {
    return "";
  }

  const limits = own.installed("rate-limit") ? own.of("rate-limit") : undefined;

  const uploadLimit =
    limits === undefined
      ? ""
      : `
  select h.allowed, h.retry_after into v_allowed, v_retry
  from better_supabase.hit_rate_limit(${sqlString(REQUEST_SCOPE)}, v_link ->> 'id',
    case when exists (select 1 from ${limits.table("rules")} q where q.${limits.col("rules", "scope")} = ${sqlString(REQUEST_SCOPE)}) then null else ${String(REQUEST_UPLOADS)} end,
    case when exists (select 1 from ${limits.table("rules")} q where q.${limits.col("rules", "scope")} = ${sqlString(REQUEST_SCOPE)}) then null else ${sqlString(REQUEST_PERIOD)}::interval end) h;
  if not v_allowed then
    raise exception 'too many uploads through this link' using errcode = 'BS429', hint = 'DRIVE_LINK_RATE_LIMITED', detail = 'retry after ' || v_retry;
  end if;`;

  const requestFunctions =
    A === undefined || attachments === undefined
      ? ""
      : `
-- Files from people outside the organization: an upload share link on a
-- folder. Needs ${roles.share} on the folder, as any share link does.
create or replace function ${fn("drive_request_files")}(folder uuid, expires_at timestamptz default null, max_uses integer default null, password text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_request_files.folder${live("x")};
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  return ${shareLinks.fn("create_share_link")}(
    tenant => v_node.${n("tenant")}, subject_type => ${typeLit}, subject_id => v_node.${n("id")}::text, role => 'upload',
    expires_at => drive_request_files.expires_at, max_uses => drive_request_files.max_uses, password => drive_request_files.password);
end;
$$;
${userGrant(`${fn("drive_request_files")}(uuid, timestamptz, integer, text)`)}

-- One file through an upload link, for the server to upload with the
-- service role and commit: { nodeId, bucket, path, attachment }. The file
-- has no creator and source 'request', and each call counts one use of the
-- link${limits === undefined ? "" : `, at most ${String(REQUEST_UPLOADS)} per ${REQUEST_PERIOD} per link unless a ${REQUEST_SCOPE} rule says otherwise`}. A link
-- with a password returns { passwordRequired: true } until the call passes it.
create or replace function ${fn("drive_link_upload")}(token text, name text, mime_type text, size bigint, password text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link jsonb := ${shareLinks.fn("resolve_share_link")}(drive_link_upload.token, drive_link_upload.password);
  v_node ${T}%rowtype;
  v_folder ${T}%rowtype;
  v_attachment jsonb;${limits === undefined ? "" : "\n  v_allowed boolean;\n  v_retry integer;"}
begin
  if v_link is null then
    ${fail("DRIVE_LINK_NOT_FOUND", "this link does not exist or has expired", "P0002")}
  end if;
  if v_link ->> 'id' is null then
    return jsonb_build_object('passwordRequired', true);
  end if;
  if v_link ->> 'subjectType' is distinct from ${typeLit} or v_link ->> 'subjectId' !~ ${UUID_TEXT} then
    ${fail("DRIVE_LINK_NOT_FOUND", "this link does not exist or has expired", "P0002")}
  end if;
  if v_link ->> 'role' is distinct from 'upload' then
    ${fail("DRIVE_LINK_ROLE_INVALID", "only an upload link takes files", "22023")}
  end if;
  select * into v_folder from ${T} x where x.${n("id")} = (v_link ->> 'subjectId')::uuid
    and x.${n("tenant")}::text = v_link ->> 'organizationId'${live("x")};
  if not found or v_folder.${n("kind")} <> 'folder' then
    ${fail("DRIVE_LINK_NOT_FOUND", "this link does not open that item", "P0002")}
  end if;
  if ${readOnly("v_folder")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;${uploadLimit}
  v_node := ${fn("drive_insert_node")}(v_folder.${n("tenant")}, ${driveColumn ? `v_folder.${n("drive")}` : "null"}, v_folder.${n("id")}, 'file', ${fn("drive_clean_name")}(drive_link_upload.name), 'rename', null, 'request');
  v_attachment := ${attachments.fn("create_attachment")}(v_node.${n("tenant")}, v_node.${n("name")}, drive_link_upload.mime_type, drive_link_upload.size, ${typeLit}, v_node.${n("id")}::text);
  return jsonb_build_object('nodeId', v_node.${n("id")}, 'bucket', v_attachment ->> 'bucket', 'path', v_attachment ->> 'object_path', 'attachment', v_attachment);
end;
$$;
revoke all on function ${fn("drive_link_upload")}(text, text, text, bigint, text) from public, anon, authenticated;
grant execute on function ${fn("drive_link_upload")}(text, text, text, bigint, text) to anon, authenticated, service_role;
`;

  return `
-- What a share link on a node opens: the node and, for a folder, its
-- children. node picks an item under the linked folder. For a file, object
-- carries the original for the server to sign a download URL with, unless the
-- link's download_allowed is false or a download block covers the file${previewColumn ? "; previews\n-- carries the rendered pages either way" : ""}. An upload link opens nothing.
create or replace function ${fn("drive_link")}(token text, node uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link_id uuid;
  v_role text;
  v_root text;
  v_expires timestamptz;
  v_tenant text;
  v_download boolean;
  v_node ${T}%rowtype;
begin
  select l.${shareLinks.col("links", "id")}, l.${shareLinks.col("links", "role")}, l.${shareLinks.col("links", "subjectId")}, l.${shareLinks.col("links", "expiresAt")}, l.${shareLinks.col("links", "tenant")}::text, ${shareLinks.has("links", "downloadAllowed") ? `l.${shareLinks.col("links", "downloadAllowed")}` : "true"}
    into v_link_id, v_role, v_root, v_expires, v_tenant, v_download
  from ${shareLinks.table("links")} l
  where ${liveShareLink(shareLinks, "l", "drive_link.token", typeLit)};
  if v_link_id is null or v_root !~ ${UUID_TEXT} then
    ${fail("DRIVE_LINK_NOT_FOUND", "this link does not exist or has expired", "P0002")}
  end if;
  select * into v_node from ${T} x where x.${n("id")} = coalesce(drive_link.node, v_root::uuid)
    and x.${n("tenant")}::text = v_tenant${live("x")};
  if not found or not (v_root::uuid = any (${fn("drive_ancestors")}(v_node.${n("id")}))) then
    ${fail("DRIVE_LINK_NOT_FOUND", "this link does not open that item", "P0002")}
  end if;
  if v_role = 'upload' then
    ${fail("DRIVE_LINK_ROLE_INVALID", "an upload link takes files and opens nothing", "22023")}
  end if;
  v_download := coalesce(v_download, true) and not ${fn("drive_download_blocked")}(v_node.${n("id")});
  return jsonb_build_object(
    'link', jsonb_build_object('id', v_link_id, 'role', v_role, 'nodeId', v_root::uuid, 'expiresAt', v_expires, 'downloadAllowed', v_download),
    'node', ${json("v_node")},
    'children', case when v_node.${n("kind")} = 'folder' then (
      select coalesce(jsonb_agg(${json("c.r")} order by ${orderBy("(c.r)")}), '[]'::jsonb)
      from (select y as r from ${T} y where y.${n("parent")} = v_node.${n("id")}${live("y")} order by ${orderBy("y")} limit 500) c
    ) end${
      A === undefined
        ? ""
        : `,
    'object', case when v_download then (select jsonb_build_object('bucket', f.${a("bucket")}, 'path', f.${a("path")}, 'mimeType', f.${a("mimeType")}, 'status', f.${a("status")})
      from ${A} f where f.${a("id")} = v_node.${n("attachment")}) end${
        previewColumn
          ? `,
    'previews', ${fn("drive_preview_json")}(v_node)`
          : ""
      }`
    }
  );
end;
$$;
revoke all on function ${fn("drive_link")}(text, uuid) from public, anon, authenticated;
grant execute on function ${fn("drive_link")}(text, uuid) to anon, authenticated, service_role;
${requestFunctions}`;
}
