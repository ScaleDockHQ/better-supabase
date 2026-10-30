import type { RowFields } from "../../core/block-fields.ts";
import type { ValidationIssue } from "../../core/errors.ts";
import type { ListQueryInput } from "../../list/list-query.ts";

export const SAVED_VIEW_KINDS = [
  "table",
  "board",
  "calendar",
  "timeline",
  "gantt",
] as const;

export type SavedViewKind = (typeof SAVED_VIEW_KINDS)[number];

export const SAVED_VIEW_SCOPES = ["user", "team", "tenant"] as const;

export type SavedViewScope = (typeof SAVED_VIEW_SCOPES)[number];

export const SAVED_VIEW_DENSITIES = [
  "compact",
  "default",
  "comfortable",
] as const;

export type SavedViewDensity = (typeof SAVED_VIEW_DENSITIES)[number];

/** Column layout, in the shape of TanStack Table's column state. */
export interface SavedViewColumns {
  readonly visible?: readonly string[];
  readonly order?: readonly string[];
  readonly sizes?: Readonly<Record<string, number>>;
  readonly pinned?: {
    readonly left?: readonly string[];
    readonly right?: readonly string[];
  };
}

/** What a view stores. `query` is the list's typed input, without the page. */
export interface SavedViewState<
  Q extends ListQueryInput<string, string> = ListQueryInput<string, string>,
> {
  readonly query?: Omit<Q, "page" | "after">;
  readonly columns?: SavedViewColumns;
  readonly grouping?: readonly string[];
  readonly density?: SavedViewDensity;
  /**
   * Settings of the layout, such as a board's group column or a calendar's date
   * field.
   */
  readonly layout?: Readonly<Record<string, unknown>>;
  /**
   * Keeps the view to the records of a collection
   * (`better-supabase/blocks/collections`): pass `collections.where(id)` as the
   * list's `where`.
   */
  readonly collectionId?: string;
}

/** The part of a view's state that lives outside the URL. */
export type SavedViewDisplayState = Omit<SavedViewState, "query">;

/** The caller's own flags for a view, which need no right to change it. */
export interface SavedViewPreference {
  /** Opens this view first, ahead of every slot default. */
  readonly isDefault: boolean;
  readonly hidden: boolean;
  readonly pinned: boolean;
}

export interface SavedViewPreferenceInput {
  readonly isDefault?: boolean;
  readonly hidden?: boolean;
  readonly pinned?: boolean;
}

export interface DuplicateViewInput {
  readonly name?: string;
  /** Default `user`. `team` and `tenant` need `saved_views.share`. */
  readonly scope?: SavedViewScope;
  /** The team, for `scope: "team"`. */
  readonly teamId?: string;
}

/**
 * The part of a `defineListQuery` definition a saved view checks its query
 * against. Any list definition fits.
 */
export interface SavedViewList {
  parse(input: object | undefined): {
    readonly ok: boolean;
    readonly issues?: readonly ValidationIssue[] | undefined;
  };
  readonly jsonSchema: Readonly<Record<string, unknown>>;
}

export interface SavedView<
  Q extends ListQueryInput<string, string> = ListQueryInput<string, string>,
  F extends object = Record<never, never>,
> {
  readonly id: string;
  readonly list: string;
  readonly scope: SavedViewScope;
  readonly ownerId: string | null;
  readonly teamId: string | null;
  readonly name: string;
  readonly kind: SavedViewKind;
  readonly state: SavedViewState<Q>;
  readonly rank: string;
  /** The default of its slot (the owner's, the team's or the tenant's). */
  readonly isDefault: boolean;
  /** The caller's own flags; all false without the preferences table. */
  readonly preference: SavedViewPreference;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
}
