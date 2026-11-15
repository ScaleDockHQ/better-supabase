import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BulkCallOptions, BulkReport } from "../../core/bulk.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type {
  DriveGrant,
  DriveNode,
  DrivePrincipal,
  DriveUpload,
  NewDriveFile,
} from "../drive/index.ts";
import type { CreatedShareLink } from "../share-links/index.ts";
import type { FilespaceParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { bulkItems } from "../../core/bulk.ts";
import { AsyncResult as Async } from "../../core/result.ts";

/**
 * The subject type `drive` registers unless `blocks.drive.options.subjectType`
 * changes it.
 */
const DRIVE_SUBJECT = "drive_node";

/** One principal of `filespace.bulkShare`. */
export interface FilespacePrincipalGrant {
  readonly principal: DrivePrincipal;
  readonly role: string;
}

/** The helpers `filespace` adds over `drive` and `share-links`. */
export interface Filespace {
  /**
   * Creates the file, hands its signed upload to `send` (which PUTs the bytes),
   * and commits it. When `send` throws, the pending file goes to the bin and
   * the error comes back as the result's `DbError`.
   */
  put(input: {
    organizationId: string;
    file: NewDriveFile;
    send: (upload: DriveUpload) => PromiseLike<void>;
  }): AsyncResult<DriveNode>;
  /**
   * Shares one node with each principal and reports per principal (ADR 1036):
   * the report names a principal as `type:id`, so a refused principal lands in
   * `failed` and the others still run. Takes at most 500 principals.
   */
  bulkShare(
    input: {
      id: string;
      principals: readonly FilespacePrincipalGrant[];
      expiresAt?: Temporal.Instant | undefined;
    },
    options?: BulkCallOptions,
  ): AsyncResult<BulkReport>;
  /**
   * Shares one node with each principal. A grant is idempotent, so a retry
   * finishes the rest.
   *
   * @deprecated Use `bulkShare`, which reports per principal and does not stop
   * at the first failure. Removed in 0.70.
   */
  shareMany(input: {
    id: string;
    principals: readonly { principal: DrivePrincipal; role: string }[];
    expiresAt?: Temporal.Instant | undefined;
  }): AsyncResult<readonly DriveGrant[]>;
  /**
   * A link anyone with the token can open, with optional expiry, password and
   * use limit.
   */
  publicLink(input: {
    id: string;
    role?: string | undefined;
    expiresAt?: Temporal.Instant | undefined;
    password?: string | undefined;
    maxUses?: number | undefined;
  }): AsyncResult<CreatedShareLink>;
}

/** What the `filespace` creator receives. */
export type FilespaceOptions = BlockContext &
  CompositeOptions<FilespaceParts> & {
    /** \`before\` and \`after\` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Filespace>>;
    /** Receives the errors \`after\` hooks throw. Default: \`console\`. */
    readonly logger?: Logger;
  };

/** Creates the `filespace` helpers over the clients of its parts. */
export function createFilespace(options: FilespaceOptions): Filespace {
  const { drive, "share-links": shareLinks } = options.parts;

  const client: Filespace = {
    put: ({ organizationId, file, send }) =>
      drive.upload({ organizationId, file }).andThen((upload) =>
        Async.from(async () => {
          try {
            await send(upload);
          } catch (error) {
            await drive.trash(upload.node.id);
            throw error;
          }

          return drive.commit({
            id: upload.node.id,
            attachmentId: upload.attachment.id,
          });
        }),
      ),

    bulkShare: ({ id, principals, expiresAt }, options) =>
      bulkItems(
        principals.map((grant) => ({
          id: `${grant.principal.type}:${grant.principal.id}`,
          ...grant,
        })),
        ({ principal, role }) =>
          drive.share({
            id,
            principal,
            role,
            ...(expiresAt === undefined ? {} : { expiresAt }),
          }),
        options,
      ),

    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1036)
    shareMany: ({ id, principals, expiresAt }) =>
      Async.from(async () => {
        const grants: DriveGrant[] = [];

        for (const { principal, role } of principals) {
          const result = await drive.share({
            id,
            principal,
            role,
            ...(expiresAt === undefined ? {} : { expiresAt }),
          });

          if (!result.ok) {
            return result;
          }

          grants.push(result.data);
        }

        return { ok: true as const, data: grants, error: null };
      }),

    publicLink: ({ id, role, expiresAt, password, maxUses }) =>
      shareLinks.create({
        subject: { type: DRIVE_SUBJECT, id },
        options: {
          ...(role === undefined ? {} : { role }),
          ...(expiresAt === undefined ? {} : { expiresAt }),
          ...(password === undefined ? {} : { password }),
          ...(maxUses === undefined ? {} : { maxUses }),
        },
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "filespace",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
