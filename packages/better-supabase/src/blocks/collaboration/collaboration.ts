import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { Comment, NewComment } from "../comments/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { CollaborationParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { ok } from "../../core/result.ts";

/** What `collaboration.discuss` returns. */
export interface Discussion {
  readonly comment: Comment;
  /** How many tags the call attached. */
  readonly tagged: number;
}

/** The helpers `collaboration` adds over its parts. */
export interface Collaboration {
  /**
   * Posts a comment on `subject`, then attaches each of `tagIds` to the
   * subject. It stops at the first failed attach and returns that error; the
   * comment stays posted, so retry the tags with `tags.attach`, not `discuss`.
   */
  discuss(input: {
    subject: RecordRef;
    comment: NewComment;
    tagIds?: readonly string[] | undefined;
  }): AsyncResult<Discussion>;
}

/** What the `collaboration` creator receives. */
export type CollaborationOptions = BlockContext &
  CompositeOptions<CollaborationParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Collaboration>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `collaboration` helpers over the clients of its parts. */
export function createCollaboration(
  options: CollaborationOptions,
): Collaboration {
  const { comments, tags } = options.parts;

  const client: Collaboration = {
    discuss: ({ subject, comment, tagIds = [] }) =>
      comments.create({ subject, comment }).andThen(async (posted) => {
        for (const tagId of tagIds) {
          const attached = await tags.attach({ record: subject, tagId });

          if (!attached.ok) {
            return attached;
          }
        }

        return ok({ comment: posted, tagged: tagIds.length });
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "collaboration",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
