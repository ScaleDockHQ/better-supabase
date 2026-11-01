import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Who reads a channel: the tenant, or its members. */
export type ChannelVisibility = "public" | "private";

const VISIBILITY: readonly ChannelVisibility[] = ["public", "private"];

/** A channel. Its `id` is also its conversation's id in `messaging`. */
export interface Channel {
  readonly id: string;
  readonly organizationId: string;
  /** Lowercase letters, digits, `-` and `_`, unique in the tenant. */
  readonly name: string;
  readonly visibility: ChannelVisibility;
  readonly topic: string | undefined;
  readonly purpose: string | undefined;
  /** The record the channel is linked to. */
  readonly subject: RecordRef | undefined;
  readonly createdBy: string | undefined;
  /** The caller's role, or `undefined` when they haven't joined. */
  readonly role: "owner" | "member" | undefined;
  readonly memberCount: number;
  readonly lastMessageAt: Temporal.Instant | undefined;
  readonly archivedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface NewChannel {
  readonly name: string;
  /** Default `public`. */
  readonly visibility?: ChannelVisibility;
  readonly topic?: string | undefined;
  readonly purpose?: string | undefined;
  /** A record to link the channel to; the caller must read it. */
  readonly subject?: RecordRef;
  /** Members besides the caller, who owns the channel. */
  readonly memberIds?: readonly string[];
}

/** A key left out keeps its value; `null` clears `topic` and `purpose`. */
export interface ChannelChange {
  readonly name?: string;
  readonly visibility?: ChannelVisibility;
  readonly topic?: string | null;
  readonly purpose?: string | null;
}

/** Every method that takes no id acts in the block's `tenant`. */
export interface Channels {
  /** Creates a channel and its conversation; the caller owns it. */
  create(channel: NewChannel): AsyncResult<Channel>;
  /** The manage key or the channel's owner. */
  update(input: {
    channelId: string;
    change: ChannelChange;
  }): AsyncResult<Channel>;
  /** Archives the channel (read-only from then on) or restores it. */
  archive(input: {
    channelId: string;
    archived?: boolean | undefined;
  }): AsyncResult<boolean>;
  /** The caller joins a public channel. */
  join(channelId: string): AsyncResult<boolean>;
  /** The caller leaves; `false` when they weren't a member. */
  leave(channelId: string): AsyncResult<boolean>;
  /** Adds members; returns how many joined. */
  invite(input: {
    channelId: string;
    userIds: readonly string[];
  }): AsyncResult<number>;
  /**
   * The caller's channels by name, with `browse` every channel they can see, or
   * with `on` the channels linked to that record that the caller can see.
   */
  list(options?: {
    readonly browse?: boolean;
    readonly includeArchived?: boolean;
    readonly on?: RecordRef;
  }): AsyncResult<Channel[]>;
  get(channelId: string): AsyncResult<Channel | undefined>;
  /** A channel by name in the tenant. */
  find(name: string): AsyncResult<Channel | undefined>;
}

export interface ChannelsOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /** The module schema, or its API schema. Default `better_supabase`. */
  readonly schema?: string;
  readonly hooks?: BlockHooks<Channels>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const ROLES = ["owner", "member"] as const;

function channelOf(value: unknown): Channel {
  const row = recordOf(value, "channel");
  const subjectType = optionalText(row["subject_type"]);
  const subjectId = optionalText(row["subject_id"]);
  const role = optionalText(row["role"]);
  const count = Number(row["memberCount"] ?? 0);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    name: textOf(row["name"]),
    visibility: enumOrThrow(row["visibility"], VISIBILITY, "visibility"),
    topic: optionalText(row["topic"]),
    purpose: optionalText(row["purpose"]),
    subject:
      subjectType === undefined || subjectId === undefined
        ? undefined
        : { type: subjectType, id: subjectId },
    createdBy: optionalText(row["created_by"]),
    role: role === undefined ? undefined : enumOrThrow(role, ROLES, "role"),
    memberCount: Number.isFinite(count) ? count : 0,
    lastMessageAt: optionalInstant(row["lastMessageAt"]),
    archivedAt: optionalInstant(row["archivedAt"]),
    createdAt: requiredInstant(row["created_at"], "createdAt"),
    updatedAt: requiredInstant(row["updated_at"], "updatedAt"),
  };
}

const maybeChannel = (value: unknown): Channel | undefined =>
  value === null || value === undefined ? undefined : channelOf(value);

/**
 * The channels block: named conversations on the messaging core, public or
 * private, with a topic, a purpose and an optional linked record. Send and read
 * their messages with the `messaging` block, by the channel's id.
 */
export function createChannels(options: ChannelsOptions): Channels {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const many = (fn: string, args: Record<string, unknown>) =>
    call(fn, args, (value) => recordsOf(value, fn).map(channelOf));

  const client: Channels = {
    create: (channel) =>
      tenant().andThen((organizationId) =>
        call(
          "create_channel",
          {
            tenant: organizationId,
            name: channel.name,
            attrs: {
              ...(channel.visibility === undefined
                ? {}
                : { visibility: channel.visibility }),
              ...(channel.topic === undefined ? {} : { topic: channel.topic }),
              ...(channel.purpose === undefined
                ? {}
                : { purpose: channel.purpose }),
              ...(channel.subject === undefined
                ? {}
                : {
                    subjectType: channel.subject.type,
                    subjectId: channel.subject.id,
                  }),
            },
            members: [...(channel.memberIds ?? [])],
          },
          channelOf,
        ),
      ),
    update: ({ channelId, change }) =>
      call("update_channel", { channel: channelId, attrs: change }, channelOf),
    archive: ({ channelId, archived = true }) =>
      call(
        "archive_channel",
        { channel: channelId, archived },
        (value) => value === true,
      ),
    join: (channelId) =>
      call("join_channel", { channel: channelId }, (value) => value === true),
    leave: (channelId) =>
      call("leave_channel", { channel: channelId }, (value) => value === true),
    invite: ({ channelId, userIds }) =>
      call(
        "invite_to_channel",
        { channel: channelId, users: [...userIds] },
        Number,
      ),
    list: (list = {}) =>
      list.on === undefined
        ? tenant().andThen((organizationId) =>
            many("list_channels", {
              tenant: organizationId,
              browse: list.browse ?? false,
              include_archived: list.includeArchived ?? false,
            }),
          )
        : many("channels_for_record", {
            subject_type: list.on.type,
            subject_id: list.on.id,
          }),
    get: (channelId) =>
      call("get_channel", { channel: channelId }, maybeChannel),
    find: (name) =>
      tenant().andThen((organizationId) =>
        call("find_channel", { tenant: organizationId, name }, maybeChannel),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "channels",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
