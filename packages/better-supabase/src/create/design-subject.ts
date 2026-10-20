import type { AppTableVersions } from "../config/index.ts";
import type { Design } from "./design.ts";
import type { SchemaColumn } from "./schema.ts";

/** Makes the rows a subject (`appTables.<table>.subject`); the shape of `AppTableSubject`. */
export interface AppSubject {
  readonly type: string;
  readonly title?: string;
  readonly url?: string;
  readonly search?: {
    readonly title?: string;
    readonly body?: readonly string[];
  };
  readonly permissions?: Readonly<Record<string, string>>;
  readonly rank?: true | { readonly group?: string };
  readonly softDelete?: boolean;
  readonly versions?: true | AppTableVersions;
}

/** Which writes emit an event and the columns its payload carries. */
export interface AppEvents {
  readonly on?: readonly ("created" | "updated" | "deleted")[];
  readonly include?: readonly string[];
}

/** The columns `subject` adds: `rank` for manual order and `deleted_at` for trash. */
export function subjectColumns(
  subject: AppSubject | undefined,
): SchemaColumn[] {
  const columns: SchemaColumn[] = [];

  if (subject?.rank !== undefined) {
    columns.push({
      name: "rank",
      type: "text",
      nullable: false,
      default: "'V'",
      unique: false,
    });
  }

  if (subject?.softDelete === true) {
    columns.push({
      name: "deleted_at",
      type: "timestamptz",
      nullable: true,
      default: null,
      unique: false,
    });
  }

  return columns;
}

type Draft<T> = { -readonly [K in keyof T]: T[K] };

/** The subject with the columns it names renamed or dropped by `edit`. */
export function subjectColumnsEdited(
  subject: AppSubject,
  edit: (columns: readonly string[]) => readonly string[],
): AppSubject {
  const { title, search, rank, versions, ...rest } = subject;
  const next: Draft<AppSubject> = { ...rest };
  const [nextTitle] = title === undefined ? [] : edit([title]);

  if (nextTitle !== undefined) {
    next.title = nextTitle;
  }

  if (search !== undefined) {
    const nextSearch: Draft<NonNullable<AppSubject["search"]>> = {};

    const [searchTitle] =
      search.title === undefined ? [] : edit([search.title]);

    const body = edit(search.body ?? []);

    if (searchTitle !== undefined) {
      nextSearch.title = searchTitle;
    }

    if (body.length > 0) {
      nextSearch.body = body;
    }

    next.search = nextSearch;
  }

  if (versions === true) {
    next.versions = true;
  } else if (versions !== undefined) {
    const { columns, ...options } = versions;
    const kept = columns === undefined ? undefined : edit(columns);

    next.versions =
      kept === undefined || kept.length === 0
        ? options
        : { ...options, columns: kept };
  }

  if (rank === true) {
    next.rank = true;
  } else if (rank !== undefined) {
    const [group] = rank.group === undefined ? [] : edit([rank.group]);

    next.rank = group === undefined ? true : { group };
  }

  return next;
}

const SUBJECT_TYPE = /^[a-z][a-z0-9_]*$/u;

/** Why `type` can't be the subject type of the app table `table`, or `undefined` when it can. */
export function subjectTypeError(
  design: Design,
  table: string,
  type: string,
): string | undefined {
  if (!SUBJECT_TYPE.test(type)) {
    return "Use lowercase letters, digits and underscores, starting with a letter.";
  }

  const owner = Object.entries(design.appTables ?? {}).find(
    ([name, each]) => name !== table && each.subject?.type === type,
  )?.[0];

  return owner === undefined
    ? undefined
    : `${owner} already has the subject type ${type}.`;
}

/** App table events with `edit` applied to the payload columns, dropping an empty list. */
export function eventsColumnsEdited(
  events: true | AppEvents,
  edit: (columns: readonly string[]) => readonly string[],
): true | AppEvents {
  if (events === true) {
    return true;
  }

  const { include, ...rest } = events;
  const kept = include === undefined ? [] : edit(include);

  return kept.length === 0 ? rest : { ...rest, include: kept };
}
