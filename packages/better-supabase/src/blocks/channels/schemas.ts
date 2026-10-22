import type { EntitySchema } from "../entity-schema.ts";
import type { ChannelChange, NewChannel } from "./channels.ts";

import { entitySchema } from "../entity-schema.ts";

const VISIBILITY = ["public", "private"] as const;

/** What `create` takes. The SQL checks the name's shape. */
export const channelInputSchema: EntitySchema<NewChannel> =
  entitySchema<NewChannel>({
    title: "NewChannel",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 80 },
      visibility: { kind: "enum", values: VISIBILITY, optional: true },
      topic: { kind: "string", maxLength: 250, optional: true },
      purpose: { kind: "string", maxLength: 250, optional: true },
      subject: {
        kind: "json",
        optional: true,
        description: "The record to link: { type, id }.",
      },
      memberIds: { kind: "uuid", optional: true, array: true },
    },
  });

/** What `update` takes. */
export const channelChangeSchema: EntitySchema<ChannelChange> =
  entitySchema<ChannelChange>({
    title: "ChannelChange",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 80, optional: true },
      visibility: { kind: "enum", values: VISIBILITY, optional: true },
      topic: { kind: "string", maxLength: 250, optional: true, nullable: true },
      purpose: {
        kind: "string",
        maxLength: 250,
        optional: true,
        nullable: true,
      },
    },
  });
