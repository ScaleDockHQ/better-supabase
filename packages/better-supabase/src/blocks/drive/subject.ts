import type { SubjectConfig } from "../../config/types/subjects.ts";

import { DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";

/**
 * The `subjects.drive_node` entry for the managed tables, so comments,
 * attachments, versions, trash and search can name drive nodes. The permission
 * keys are the tenant-wide floor; grants decide per node, through
 * `drive_node_readable` for reads, `drive_can_comment` for comments and
 * `drive_node_writable` for custom field writes, and custom field values follow
 * the node's read grants. Search indexes each node's name and the start of the
 * text `createDriveText` stored for it, through the `drive_node_search` view.
 *
 * `accessRequests` lets members ask for access to a node through the
 * access-requests block: it declares the record team those requests need
 * (`read` by default), and an approved request becomes a node grant instead of
 * a team row.
 */
export function driveSubject(
  options: {
    readonly schema?: string;
    /** `blocks.drive.tables.nodes`. Default `drive_nodes`. */
    readonly table?: string;
    /** `blocks.drive.columns.nodes.tenant`. Default `tenant_id`. */
    readonly tenant?: string;
    /** The actions members may request, or `true` for `["read"]`. */
    readonly accessRequests?: true | readonly ("read" | "comment" | "write")[];
  } = {},
): SubjectConfig {
  const schema = options.schema ?? DEFAULT_BLOCK_SCHEMA;

  return {
    table: `${schema}.${options.table ?? "drive_nodes"}`,
    idType: "uuid",
    tenant: options.tenant ?? "tenant_id",
    title: "name",
    deletedAt: "deleted_at",
    permissions: {
      read: { key: "drive.read", check: `${schema}.drive_node_readable` },
      write: "drive.manage",
      comment: { check: `${schema}.drive_can_comment` },
      fields: { check: `${schema}.drive_node_writable` },
    },
    readAccess: "record",
    ...(options.accessRequests === undefined
      ? {}
      : {
          team: {
            actions:
              options.accessRequests === true
                ? ["read"]
                : options.accessRequests,
          },
        }),
    search: {
      title: "name",
      body: ["content"],
      from: { view: `${schema}.drive_node_search`, key: "id" },
      watch: [{ table: `${schema}.drive_node_texts`, key: "node_id" }],
    },
  };
}
