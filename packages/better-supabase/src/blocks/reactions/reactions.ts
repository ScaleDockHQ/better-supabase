import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface ReactionsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** `blocks.reactions.schema`, or the API schema of its wrappers. */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Reactions>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** One emoji on a subject. */
export interface ReactionCount {
  /** The emoji, or a custom emoji's `:shortcode:`. */
  readonly emoji: string;
  readonly count: number;
  /** Whether the signed-in user reacted with it. */
  readonly reacted: boolean;
  /** The first ten actors (user ids, or names the service passed), oldest first. */
  readonly actors: readonly string[];
}

export interface CustomEmoji {
  readonly id: string;
  /** Without the colons: `party-parrot` is used as `:party-parrot:`. */
  readonly shortcode: string;
  /** An attachment from the `attachments` module. */
  readonly attachmentId?: string;
  /** An `https://` image URL. */
  readonly url?: string;
  readonly createdAt: Temporal.Instant;
}

export interface CustomEmojiInput {
  readonly shortcode: string;
  readonly attachmentId?: string;
  readonly url?: string;
}

export interface ReactOptions {
  /** `false` removes the reaction. Default: `true`. */
  readonly present?: boolean;
  /** The service role reacts for this actor (default `service`). */
  readonly actor?: string;
}

export interface Reactions {
  /** Adds or removes the caller's reaction; returns the subject's reactions. */
  react(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    emoji: string,
    options?: ReactOptions,
  ): AsyncResult<readonly ReactionCount[]>;
  /** The reactions of up to 200 subjects of one type, by subject id. */
  summary(
    organizationId: string,
    subjectType: string,
    subjectIds: readonly string[],
  ): AsyncResult<Readonly<Record<string, readonly ReactionCount[]>>>;
  /** The organization's custom emoji, by shortcode. */
  customEmoji(organizationId: string): AsyncResult<readonly CustomEmoji[]>;
  /** Adds a custom emoji, or replaces the image of an existing shortcode. */
  saveCustomEmoji(
    organizationId: string,
    input: CustomEmojiInput,
  ): AsyncResult<CustomEmoji>;
  /** Deletes a custom emoji and the reactions that used it. */
  deleteCustomEmoji(id: string): AsyncResult<boolean>;
}

/** The topic the module broadcasts an organization's reaction changes to. */
export function reactionsTopic(
  organizationId: string,
  topic = "reactions",
): string {
  return `${topic}:${organizationId}`;
}

function countsOf(value: unknown, fn: string): readonly ReactionCount[] {
  return recordsOf(value, fn).map((row) => ({
    emoji: textOf(row["emoji"]),
    count: Number(row["count"]),
    reacted: row["reacted"] === true,
    actors: Array.isArray(row["actors"])
      ? row["actors"].map((actor) => textOf(actor))
      : [],
  }));
}

function emojiOf(value: unknown, fn: string): CustomEmoji {
  const row = recordOf(value, fn);
  const attachmentId = optionalText(row["attachmentId"]);
  const url = optionalText(row["url"]);
  return {
    id: textOf(row["id"]),
    shortcode: textOf(row["shortcode"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...(attachmentId === undefined ? {} : { attachmentId }),
    ...(url === undefined ? {} : { url }),
  };
}

/** The `reactions` SQL module as typed calls. */
export function createReactions(options: ReactionsOptions): Reactions {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: Reactions = {
    react: (organizationId, subjectType, subjectId, emoji, react = {}) =>
      call(
        "react",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          emoji,
          present: react.present ?? true,
          actor: react.actor ?? null,
        },
        (value) => countsOf(value, "react"),
      ),
    summary: (organizationId, subjectType, subjectIds) =>
      call(
        "reaction_summary",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_ids: [...subjectIds],
        },
        (value) =>
          Object.fromEntries(
            Object.entries(recordOf(value, "reaction_summary")).map(
              ([id, counts]) => [id, countsOf(counts, "reaction_summary")],
            ),
          ),
      ),
    customEmoji: (organizationId) =>
      call("list_custom_emoji", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_custom_emoji").map((row) =>
          emojiOf(row, "list_custom_emoji"),
        ),
      ),
    saveCustomEmoji: (organizationId, input) =>
      call(
        "save_custom_emoji",
        {
          tenant: organizationId,
          shortcode: input.shortcode,
          attachment_id: input.attachmentId ?? null,
          url: input.url ?? null,
        },
        (value) => emojiOf(value, "save_custom_emoji"),
      ),
    deleteCustomEmoji: (id) =>
      call("delete_custom_emoji", { emoji_id: id }, (value) => value === true),
  };
  return withBlockHooks(client, options.hooks, {
    block: "reactions",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
