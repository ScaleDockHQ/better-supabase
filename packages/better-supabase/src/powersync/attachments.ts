import type { CreateUploadRepository, UploadFunction } from "./connector.ts";

import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";

/** The columns an attachment insert accepts, besides `id`. */
const WRITABLE = [
  "organization_id",
  "bucket",
  "subject_type",
  "subject_id",
  "name",
  "mime_type",
  "size",
  "metadata",
  "width",
  "height",
  "pages",
] as const;

const DEFAULT_PATH = "{organization_id}/attachments/{id}";

export interface AttachmentQueueRouteOptions {
  /**
   * `blocks.attachments.options.path`, for `path()`. Default
   * `{organization_id}/attachments/{id}`.
   */
  readonly path?: string;
  /** `blocks.attachments.options.extraColumns` a `PUT` sends too. */
  readonly extraColumns?: readonly string[];
}

/** The attachment columns `path()` reads, as PowerSync syncs them. */
export interface AttachmentPathRow {
  readonly id: string;
  readonly organization_id?: string | null;
  readonly subject_type?: string | null;
  readonly subject_id?: string | null;
  readonly name?: string | null;
  readonly version?: number | null;
}

/** An upload route for the attachments table, with the object path builder. */
export interface AttachmentQueueRoute extends UploadFunction {
  /**
   * The object path of the row's current version, the same as the database's
   * `object_path`: give it to PowerSync's `AttachmentQueue` as the file's
   * storage path.
   */
  path(row: AttachmentPathRow): string;
}

const PLACEHOLDER = /\{([a-z_]+)\}/g;

function placeholder(row: AttachmentPathRow, key: string): string {
  switch (key) {
    case "id": {
      return row.id;
    }

    case "organization_id": {
      return row.organization_id ?? "-";
    }

    case "subject_type": {
      return row.subject_type ?? "-";
    }

    case "subject_id": {
      return row.subject_id ?? "-";
    }

    case "ext": {
      return (
        /\.([a-z0-9]{1,10})$/.exec((row.name ?? "").toLowerCase())?.[1] ?? ""
      );
    }

    default: {
      throw new TypeError(
        `better-supabase: {${key}} is not an attachments path placeholder`,
      );
    }
  }
}

/**
 * Replays the attachments table for `createUploadConnector`, with
 * `blocks.attachments.options.offline` on: a `PUT` inserts the record under the
 * id the client chose, counting a `conflict` as applied, and a `DELETE` removes
 * the record first, which queues its files for deletion. A `PATCH` fails with
 * `unsupported`. Upload the file to `route.path(row)`; the storage trigger
 * marks the record uploaded.
 *
 * ```ts
 * const attachments = attachmentQueueRoute(server.db.attachments);
 * tables: { attachments },
 * ```
 */
export function attachmentQueueRoute(
  repository: CreateUploadRepository<never, never>,
  options?: AttachmentQueueRouteOptions,
): AttachmentQueueRoute;
export function attachmentQueueRoute(
  repository: CreateUploadRepository,
  options: AttachmentQueueRouteOptions = {},
): AttachmentQueueRoute {
  const template = options.path ?? DEFAULT_PATH;
  const columns = [...WRITABLE, ...(options.extraColumns ?? [])];

  const route: UploadFunction = async (entry) => {
    switch (entry.op) {
      case "PUT": {
        const data = entry.opData ?? {};

        const row: Record<string, unknown> = { id: entry.id };

        for (const column of columns) {
          if (data[column] !== undefined) {
            row[column] = data[column];
          }
        }

        const result = await repository.create(row);

        return !result.ok && result.error.kind === "conflict"
          ? ok(undefined)
          : result;
      }

      case "DELETE": {
        const result = await repository.delete(entry.id);

        return !result.ok && result.error.kind === "not_found"
          ? ok(undefined)
          : result;
      }

      default: {
        return err(
          dbError(
            "unsupported",
            `better-supabase: attachmentQueueRoute can't replay PowerSync op ${entry.op}; attachments are written once`,
          ),
        );
      }
    }
  };

  return Object.assign(route, {
    path: (row: AttachmentPathRow): string => {
      const base = template.replaceAll(PLACEHOLDER, (_, key: string) =>
        placeholder(row, key),
      );

      return (row.version ?? 1) > 1 ? `${base}-v${String(row.version)}` : base;
    },
  });
}
