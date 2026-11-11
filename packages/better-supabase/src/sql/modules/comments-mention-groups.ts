import type { BlockSqlContext } from "../context.ts";

import { isRecord } from "../../core/guards.ts";

interface MentionGroups {
  readonly table: string;
  readonly group: string;
  readonly member: string;
  readonly tenant?: string;
}

const MENTION_GROUP_KEYS = new Set(["table", "group", "member", "tenant"]);

export function mentionGroupsOf(
  ctx: BlockSqlContext,
): MentionGroups | undefined {
  const option = ctx.option("mentionGroups");

  if (option === undefined) {
    return undefined;
  }

  const where = "blocks.comments.options.mentionGroups";

  if (!isRecord(option)) {
    throw new TypeError(`${where} must be { table, group, member, tenant? }`);
  }

  for (const key of Object.keys(option)) {
    if (!MENTION_GROUP_KEYS.has(key)) {
      throw new TypeError(
        `${where}.${key} is not an option. Options: table, group, member, tenant`,
      );
    }
  }

  const text = (key: string): string | undefined => {
    const value = option[key];

    if (value === undefined) {
      return undefined;
    }

    if (typeof value !== "string" || value.length === 0) {
      throw new TypeError(`${where}.${key} must be a non-empty string`);
    }

    return value;
  };

  const table = text("table");
  const group = text("group");
  const member = text("member");

  if (table === undefined || group === undefined || member === undefined) {
    throw new TypeError(`${where} needs table, group and member`);
  }

  const tenant = text("tenant");

  return { table, group, member, ...(tenant !== undefined && { tenant }) };
}
