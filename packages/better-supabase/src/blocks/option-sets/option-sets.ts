import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { rankBetweenResult } from "../../core/rank-result.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

export interface OptionSetItem {
  readonly id: string;
  readonly optionSetId: string;
  readonly key: string;
  /** The key the item was seeded with, which renames keep. */
  readonly systemKey?: string;
  readonly label: string;
  readonly color?: string;
  readonly icon?: string;
  readonly description?: string;
  readonly rank: string;
  /** The number written to the record's level column. */
  readonly level: number;
}

export interface OptionSet {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly field: string;
  readonly scopeId?: string;
  readonly key: string;
  readonly name: string;
  readonly isDefault: boolean;
  /** Its active items in order. */
  readonly items: readonly OptionSetItem[];
}

export interface OptionSetInput {
  /** Leave out to create a set. */
  readonly id?: string;
  readonly subjectType: string;
  readonly field: string;
  readonly key: string;
  readonly name: string;
  readonly scopeId?: string;
  readonly isDefault?: boolean;
}

export interface OptionSetItemInput {
  /** Leave out to add an item at the end. */
  readonly id?: string;
  readonly key: string;
  readonly label: string;
  readonly level: number;
  readonly color?: string;
  readonly icon?: string;
  readonly description?: string;
}

export interface OptionSets {
  /** The organization's active sets of a subject type, with their items. */
  list(input: {
    organizationId: string;
    subjectType: string;
    field?: string | undefined;
  }): AsyncResult<OptionSet[]>;
  /**
   * The default set of a bound field, created from the binding's items (or its
   * brand's) on first use. Calling it on every start is safe.
   */
  ensure(input: {
    organizationId: string;
    subjectType: string;
    field: string;
    scopeId?: string | undefined;
  }): AsyncResult<OptionSet>;
  /** Creates or renames a set. */
  upsert(input: {
    organizationId: string;
    input: OptionSetInput;
  }): AsyncResult<OptionSet>;
  /** Adds an item at the end of a set, or changes one. */
  saveItem(input: {
    optionSetId: string;
    input: OptionSetItemInput;
  }): AsyncResult<OptionSetItem>;
  /** Moves an item between the items with rank keys `previous` and `next`. */
  reorderItem(input: {
    itemId: string;
    neighbors: RankNeighbors;
  }): AsyncResult<string>;
  /**
   * Archives an item. Records that use it move to `replacementId`; without one,
   * an item that is in use is refused.
   */
  archiveItem(input: {
    itemId: string;
    replacementId?: string | undefined;
  }): AsyncResult<boolean>;
  /** Brings an archived item back; records that moved away stay where they are. */
  restoreItem(itemId: string): AsyncResult<boolean>;
}

export interface OptionSetsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<OptionSets>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

function itemOf(value: unknown): OptionSetItem {
  const row = recordOf(value, "option set item");
  const systemKey = optionalText(row["system_key"]);
  const color = optionalText(row["color"]);
  const icon = optionalText(row["icon"]);
  const description = optionalText(row["description"]);

  return {
    id: textOf(row["id"]),
    optionSetId: textOf(row["option_set_id"]),
    key: textOf(row["key"]),
    label: textOf(row["label"]),
    rank: textOf(row["rank"]),
    level: numberOf(row["level"]) ?? 0,
    ...(systemKey === undefined ? {} : { systemKey }),
    ...(color === undefined ? {} : { color }),
    ...(icon === undefined ? {} : { icon }),
    ...(description === undefined ? {} : { description }),
  };
}

function setOf(value: unknown): OptionSet {
  const row = recordOf(value, "option set");
  const scopeId = optionalText(row["scope_id"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    subjectType: textOf(row["subject_type"]),
    field: textOf(row["field"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    isDefault: row["is_default"] === true,
    items: recordsOf(row["items"] ?? [], "option set items").map(itemOf),
    ...(scopeId === undefined ? {} : { scopeId }),
  };
}

/**
 * The option-sets block: tenant-editable items for the fields
 * `blocks.option-sets.on` binds, such as a priority with its own levels. A
 * record stores the chosen item, and a trigger writes the item's level to the
 * field's own column.
 */
export function createOptionSets(options: OptionSetsOptions): OptionSets {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: OptionSets = {
    list: ({ organizationId, subjectType, field }) =>
      call(
        "list_option_sets",
        {
          tenant: organizationId,
          filters: {
            subject_type: subjectType,
            ...(field === undefined ? {} : { field }),
          },
        },
        (value) => recordsOf(value, "list_option_sets").map(setOf),
      ),
    ensure: ({ organizationId, subjectType, field, scopeId }) =>
      call(
        "ensure_option_set",
        {
          tenant: organizationId,
          subject_type: subjectType,
          field,
          scope_id: scopeId ?? null,
        },
        setOf,
      ),
    upsert: ({ organizationId, input }) =>
      call(
        "save_option_set",
        {
          tenant: organizationId,
          option_set: input.id ?? null,
          subject_type: input.subjectType,
          field: input.field,
          key: input.key,
          name: input.name,
          scope_id: input.scopeId ?? null,
          is_default: input.isDefault ?? null,
        },
        setOf,
      ),
    saveItem: ({ optionSetId, input }) =>
      call(
        "save_option_set_item",
        {
          option_set: optionSetId,
          item: input.id ?? null,
          key: input.key,
          label: input.label,
          level: input.level,
          color: input.color ?? null,
          icon: input.icon ?? null,
          description: input.description ?? null,
        },
        itemOf,
      ),
    reorderItem: ({ itemId, neighbors }) => {
      const key = rankBetweenResult(neighbors);

      if (!key.ok) {
        return AsyncResult.err(key.error);
      }

      return call(
        "rank_option_set_item",
        { item: itemId, rank: key.data },
        () => key.data,
      );
    },
    archiveItem: ({ itemId, replacementId }) =>
      call(
        "archive_option_set_item",
        { item: itemId, replacement: replacementId ?? null },
        (value) => value === true,
      ),
    restoreItem: (itemId) =>
      call(
        "restore_option_set_item",
        { item: itemId },
        (value) => value === true,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "option-sets",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
