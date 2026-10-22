import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockTemporalOptions, BlockTenantOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { bySubjectType } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  applyTemporal,
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface ReactionsOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
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

/** A subject's votes. */
export interface VoteTally {
  /** Up votes minus down votes. */
  readonly score: number;
  readonly up: number;
  readonly down: number;
  /** The signed-in user's vote: `1`, `-1`, or `0` for none. */
  readonly vote: -1 | 0 | 1;
}

/** `1` votes up, `-1` down, `0` clears the vote. */
export type VoteValue = -1 | 0 | 1;

export interface VoteOptions {
  /** The service role votes for this actor (default `service`). */
  readonly actor?: string;
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

/** Every method but `deleteCustomEmoji` acts in the block's `tenant`. */
export interface Reactions {
  /** Adds or removes the caller's reaction; returns the subject's reactions. */
  react(
    subject: SubjectRef,
    emoji: string,
    options?: ReactOptions,
  ): AsyncResult<readonly ReactionCount[]>;
  /**
   * The reactions of `subjects` (up to 200 of each type), keyed by
   * `subjectKey(subject)` (`type:id`). Subjects without reactions may be left
   * out.
   */
  summary(
    subjects: readonly SubjectRef[],
  ): AsyncResult<Readonly<Record<string, readonly ReactionCount[]>>>;
  /**
   * Sets the caller's vote on `subject` and returns its tally. Votes use the
   * `create` permission and the subject's read rules, like `react`.
   */
  vote(
    subject: SubjectRef,
    value: VoteValue,
    options?: VoteOptions,
  ): AsyncResult<VoteTally>;
  /**
   * The vote tallies of `subjects` (up to 200 of each type), keyed by
   * `subjectKey(subject)`.
   */
  votes(
    subjects: readonly SubjectRef[],
  ): AsyncResult<Readonly<Record<string, VoteTally>>>;
  /** The tenant's custom emoji, by shortcode. */
  customEmoji(): AsyncResult<readonly CustomEmoji[]>;
  /** Adds a custom emoji, or replaces the image of an existing shortcode. */
  saveCustomEmoji(input: CustomEmojiInput): AsyncResult<CustomEmoji>;
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

function voteOf(value: unknown): -1 | 0 | 1 {
  const vote = Number(value);

  return vote === 1 || vote === -1 ? vote : 0;
}

function tallyOf(value: unknown, fn: string): VoteTally {
  const row = recordOf(value, fn);

  return {
    score: Number(row["score"] ?? 0),
    up: Number(row["up"] ?? 0),
    down: Number(row["down"] ?? 0),
    vote: voteOf(row["vote"]),
  };
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

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: Reactions = {
    react: (subject, emoji, react = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "react",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            emoji,
            present: react.present ?? true,
            actor: react.actor ?? null,
          },
          (value) => countsOf(value, "react"),
        ),
      ),
    summary: (subjects) =>
      tenant().andThen((organizationId) =>
        bySubjectType(subjects, (type, ids) =>
          call(
            "reaction_summary",
            {
              tenant: organizationId,
              subject_type: type,
              subject_ids: [...ids],
            },
            (value) =>
              Object.fromEntries(
                Object.entries(recordOf(value, "reaction_summary")).map(
                  ([id, counts]) => [id, countsOf(counts, "reaction_summary")],
                ),
              ),
          ),
        ),
      ),
    vote: (subject, value, vote = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "vote",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            value,
            actor: vote.actor ?? null,
          },
          (result) => tallyOf(result, "vote"),
        ),
      ),
    votes: (subjects) =>
      tenant().andThen((organizationId) =>
        bySubjectType(subjects, (type, ids) =>
          call(
            "vote_summary",
            {
              tenant: organizationId,
              subject_type: type,
              subject_ids: [...ids],
            },
            (value) =>
              Object.fromEntries(
                Object.entries(recordOf(value, "vote_summary")).map(
                  ([id, tally]) => [id, tallyOf(tally, "vote_summary")],
                ),
              ),
          ),
        ),
      ),
    customEmoji: () =>
      tenant().andThen((organizationId) =>
        call("list_custom_emoji", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_custom_emoji").map((row) =>
            emojiOf(row, "list_custom_emoji"),
          ),
        ),
      ),
    saveCustomEmoji: (input) =>
      tenant().andThen((organizationId) =>
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
      ),
    deleteCustomEmoji: (id) =>
      call("delete_custom_emoji", { emoji_id: id }, (value) => value === true),
  };

  return withBlockHooks(client, options.hooks, {
    block: "reactions",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
