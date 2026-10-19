import { type Preset, resolvePreset } from "better-supabase/preset";

import type { AppSubject, AppTable, Design } from "./design";

import { singular, updateTable } from "./design";

/** A feature an app table's rows get by being a subject (`appTables.<name>.subject`). */
export type RecordFeature =
  | "comments"
  | "attachments"
  | "tags"
  | "versions"
  | "search"
  | "order"
  | "trash";

export interface RecordFeatureInfo {
  readonly feature: RecordFeature;
  readonly label: string;
  readonly description: string;
  /** The block that serves it. */
  readonly block: string;
  /** The subject key it sets, when it is per table; the others reach every subject. */
  readonly key?: "search" | "rank" | "softDelete";
  /** The column the subject adds for it. */
  readonly column?: string;
}

export const RECORD_FEATURES: readonly RecordFeatureInfo[] = [
  {
    feature: "comments",
    label: "Comments",
    description: "Threads, replies and mentions on each row.",
    block: "comments",
  },
  {
    feature: "attachments",
    label: "Attachments",
    description: "Files linked to each row, in a private bucket.",
    block: "attachments",
  },
  {
    feature: "tags",
    label: "Tags",
    description: "Tenant tags on each row.",
    block: "tags",
  },
  {
    feature: "versions",
    label: "Versions",
    description: "Numbered snapshots of each row you can restore.",
    block: "versions",
  },
  {
    feature: "search",
    label: "Search",
    description: "Indexes the title column in the search block.",
    block: "search",
    key: "search",
  },
  {
    feature: "order",
    label: "Manual order",
    description: "Adds a rank column for drag-to-reorder.",
    block: "rank",
    key: "rank",
    column: "rank",
  },
  {
    feature: "trash",
    label: "Trash",
    description: "Adds deleted_at, so a delete can be undone.",
    block: "trash",
    key: "softDelete",
    column: "deleted_at",
  },
];

const TITLE_COLUMNS = ["name", "title", "label", "subject"];

/** The column a new subject shows as its title: a likely name, then the first text column. */
function titleColumn(table: AppTable): string | undefined {
  const text = Object.entries(table.columns ?? {})
    .filter(([, column]) => column.type === "text")
    .map(([name]) => name);

  return TITLE_COLUMNS.find((name) => text.includes(name)) ?? text[0];
}

/** The subject a table gets when a feature turns it on. */
export function newSubject(name: string, table: AppTable): AppSubject {
  const title = titleColumn(table);

  return title === undefined
    ? { type: singular(name) }
    : { type: singular(name), title };
}

function hasKey(subject: AppSubject, info: RecordFeatureInfo): boolean {
  switch (info.key) {
    case undefined: {
      return true;
    }

    case "search": {
      return subject.search !== undefined;
    }

    case "rank": {
      return subject.rank !== undefined;
    }

    case "softDelete": {
      return subject.softDelete === true;
    }

    default: {
      const unreachable: never = info.key;

      return unreachable;
    }
  }
}

/** The features a table has: it is a subject, has the feature's key and the block is installed. */
export function tableFeatures(
  table: AppTable,
  installed: ReadonlySet<string>,
): readonly RecordFeatureInfo[] {
  const { subject } = table;

  return subject === undefined
    ? []
    : RECORD_FEATURES.filter(
        (info) => installed.has(info.block) && hasKey(subject, info),
      );
}

/** Why `info` can't be turned on for `table`, or `undefined` when it can. */
export function featureBlocker(
  table: AppTable,
  info: RecordFeatureInfo,
): string | undefined {
  const on = table.subject !== undefined && hasKey(table.subject, info);

  return info.column !== undefined &&
    !on &&
    Object.hasOwn(table.columns ?? {}, info.column)
    ? `Rename the ${info.column} column first; ${info.label.toLowerCase()} adds its own.`
    : undefined;
}

function withKey(
  subject: AppSubject,
  info: RecordFeatureInfo,
  on: boolean,
): AppSubject {
  if (info.key === undefined) {
    return subject;
  }

  const { [info.key]: _removed, ...rest } = subject;

  if (!on) {
    return rest;
  }

  switch (info.key) {
    case "search": {
      return { ...rest, search: {} };
    }

    case "rank":
    case "softDelete": {
      return { ...rest, [info.key]: true };
    }

    default: {
      const unreachable: never = info.key;

      return unreachable;
    }
  }
}

export interface FeatureChange {
  readonly design: Design;
  readonly blocks: readonly string[];
}

/**
 * Turns `feature` on or off for app table `name`. On makes the table a
 * subject and adds the block; off removes the table's key, or the block
 * when the feature reaches every subject.
 */
export function setFeature(
  design: Design,
  blocks: readonly string[],
  name: string,
  feature: RecordFeature,
  on: boolean,
): FeatureChange {
  const table = design.appTables?.[name];
  const info = RECORD_FEATURES.find((each) => each.feature === feature);

  if (table === undefined || info === undefined) {
    return { design, blocks };
  }

  if (on) {
    const subject = withKey(
      table.subject ?? newSubject(name, table),
      info,
      true,
    );

    return {
      design: updateTable(design, name, { subject }),
      blocks: blocks.includes(info.block) ? blocks : [...blocks, info.block],
    };
  }

  if (info.key === undefined || table.subject === undefined) {
    return { design, blocks: blocks.filter((each) => each !== info.block) };
  }

  return {
    design: updateTable(design, name, {
      subject: withKey(table.subject, info, false),
    }),
    blocks,
  };
}

/** The blocks the preset installs, its own and the ones they require. */
export function installedBlocks(preset: Preset): ReadonlySet<string> {
  return new Set(resolvePreset(preset).blocks.map((block) => block.name));
}

/** The block app table events go through. */
export const EVENTS_BLOCK = "outbox";

/**
 * Turns outbox events on or off for app table `name`. On sets `events` and
 * adds the outbox block; off removes the key and keeps the block, which
 * other blocks may write to.
 */
export function setEvents(
  design: Design,
  blocks: readonly string[],
  name: string,
  on: boolean,
): FeatureChange {
  if (design.appTables?.[name] === undefined) {
    return { design, blocks };
  }

  return {
    design: updateTable(design, name, { events: on ? true : undefined }),
    blocks:
      on && !blocks.includes(EVENTS_BLOCK) ? [...blocks, EVENTS_BLOCK] : blocks,
  };
}
