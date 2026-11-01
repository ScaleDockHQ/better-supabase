import type {
  BlockFields,
  FieldsOf,
  RowFields,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper, ValidationIssue } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { ListQueryInput } from "../../list/list-query.ts";
import type {
  DuplicateViewInput,
  SavedView,
  SavedViewKind,
  SavedViewList,
  SavedViewPreference,
  SavedViewPreferenceInput,
  SavedViewScope,
  SavedViewState,
} from "./types.ts";

import {
  blockFields,
  readAllFields,
  readFields,
  rowFields,
  writeFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { rankBetweenResult } from "../../core/rank-result.ts";
import { AsyncResult } from "../../core/result.ts";
import { blockCall, isRecord, recordOf, recordsOf, textOf } from "../shared.ts";
import { preferenceOf, viewOf } from "./rows.ts";
import { SAVED_VIEW_DENSITIES, SAVED_VIEW_SCOPES } from "./types.ts";

/**
 * What `upsert` and `duplicate` resolve to: the view's id, rank key and extra
 * columns.
 */
export interface SavedViewRef<F extends object = Record<never, never>> {
  readonly id: string;
  readonly rank: string;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
}

export interface SaveViewInput<
  Q extends ListQueryInput<string, string> = ListQueryInput<string, string>,
  F extends object = Record<never, never>,
> {
  readonly organizationId: string;
  /** The list's key, such as `tasks`; also the key in `lists`. */
  readonly list: string;
  readonly name: string;
  readonly state: SavedViewState<Q>;
  /** Default `table`. */
  readonly kind?: SavedViewKind;
  /** Default `user`. `team` and `tenant` need `saved_views.share`. */
  readonly scope?: SavedViewScope;
  /** The team, for `scope: "team"`. */
  readonly teamId?: string;
  /** Updates this view instead of adding one. */
  readonly id?: string;
  /**
   * Values for the app's extra columns (`options.extraColumns`); left out keeps
   * the stored ones.
   */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export interface SavedViewsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** List definitions by key; `upsert` checks a view's query against its list. */
  readonly lists?: Readonly<Record<string, SavedViewList>>;
  /**
   * A Standard Schema for the extra columns of the saved views table
   * (`blocks.saved-views.options.extraColumns`): writes are validated, reads
   * parsed.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<SavedViews<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export interface SavedViews<F extends object = Record<never, never>> {
  /** Adds a view, or updates `input.id`. Resolves to its id and rank key. */
  upsert(
    input: SaveViewInput<ListQueryInput<string, string>, F>,
  ): AsyncResult<SavedViewRef<F>>;
  /** The views the caller sees for a list, in rank order. */
  list(input: {
    organizationId: string;
    list: string;
  }): AsyncResult<SavedView<ListQueryInput<string, string>, F>[]>;
  /** Moves a view between its neighbours' rank keys. Resolves to its new key. */
  reorder(input: { id: string; neighbors: RankNeighbors }): AsyncResult<string>;
  /**
   * Makes a view the default of its slot (the user's, the team's or the
   * tenant's).
   */
  setDefault(input: {
    id: string;
    on?: boolean | undefined;
  }): AsyncResult<boolean>;
  /**
   * Sets the caller's own flags on a view they see. Omitted flags keep their
   * value; one preferred default per user and list.
   */
  setPreference(input: {
    id: string;
    preference: SavedViewPreferenceInput;
  }): AsyncResult<SavedViewPreference>;
  /**
   * Copies a view the caller sees as a new view. Resolves to its id and rank
   * key.
   */
  duplicate(input: {
    id: string;
    input?: DuplicateViewInput | undefined;
  }): AsyncResult<SavedViewRef<F>>;
  delete(id: string): AsyncResult<boolean>;
}

const strings = (value: unknown): value is readonly string[] =>
  Array.isArray(value) && value.every((item) => typeof item === "string");

function columnIssues(value: unknown): ValidationIssue[] {
  if (value === undefined) {
    return [];
  }

  if (!isRecord(value)) {
    return [{ message: "columns must be an object", path: ["columns"] }];
  }

  const issues: ValidationIssue[] = [];

  for (const key of ["visible", "order"] as const) {
    if (value[key] !== undefined && !strings(value[key])) {
      issues.push({
        message: `columns.${key} must be a list of column ids`,
        path: ["columns", key],
      });
    }
  }

  const sizes = value["sizes"];

  if (
    sizes !== undefined &&
    !(isRecord(sizes) && Object.values(sizes).every(Number.isFinite))
  ) {
    issues.push({
      message: "columns.sizes must map column ids to numbers",
      path: ["columns", "sizes"],
    });
  }

  const pinned = value["pinned"];

  if (
    pinned !== undefined &&
    !(
      isRecord(pinned) &&
      (pinned["left"] === undefined || strings(pinned["left"])) &&
      (pinned["right"] === undefined || strings(pinned["right"]))
    )
  ) {
    issues.push({
      message: "columns.pinned must have left and right lists",
      path: ["columns", "pinned"],
    });
  }

  return issues;
}

/**
 * Checks a view's state, and its `query` against `list` when given. An empty
 * list means the state is valid.
 */
export function savedViewIssues(
  state: unknown,
  list?: SavedViewList,
): readonly ValidationIssue[] {
  if (!isRecord(state)) {
    return [{ message: "state must be an object" }];
  }

  const issues = columnIssues(state["columns"]);

  if (state["grouping"] !== undefined && !strings(state["grouping"])) {
    issues.push({
      message: "grouping must be a list of column ids",
      path: ["grouping"],
    });
  }

  const density = state["density"];

  if (
    density !== undefined &&
    !SAVED_VIEW_DENSITIES.some((item) => item === density)
  ) {
    issues.push({
      message: `density must be one of ${SAVED_VIEW_DENSITIES.join(", ")}`,
      path: ["density"],
    });
  }

  if (state["layout"] !== undefined && !isRecord(state["layout"])) {
    issues.push({ message: "layout must be an object", path: ["layout"] });
  }

  if (
    state["collectionId"] !== undefined &&
    typeof state["collectionId"] !== "string"
  ) {
    issues.push({
      message: "collectionId must be a collection id",
      path: ["collectionId"],
    });
  }

  const query = state["query"];

  if (query !== undefined) {
    if (!isRecord(query)) {
      issues.push({ message: "query must be an object", path: ["query"] });
    } else if (list) {
      const parsed = list.parse(withoutPage(query));

      for (const issue of parsed.ok ? [] : (parsed.issues ?? [])) {
        issues.push({
          message: issue.message,
          path: ["query", ...(issue.path ?? [])],
        });
      }
    }
  }

  return issues;
}

/** The JSON Schema of a view's state, with `query` from the list's schema. */
export function savedViewStateSchema(
  list?: SavedViewList,
): Readonly<Record<string, unknown>> {
  const ids = { type: "array", items: { type: "string" } };

  return {
    $schema: "https://json-schema.org/draft/2020-12/schema",
    type: "object",
    properties: {
      query: list ? list.jsonSchema : { type: "object" },
      columns: {
        type: "object",
        properties: {
          visible: ids,
          order: ids,
          sizes: { type: "object", additionalProperties: { type: "number" } },
          pinned: {
            type: "object",
            properties: { left: ids, right: ids },
            additionalProperties: false,
          },
        },
        additionalProperties: false,
      },
      grouping: ids,
      density: { enum: [...SAVED_VIEW_DENSITIES] },
      layout: { type: "object" },
      collectionId: { type: "string", format: "uuid" },
    },
  };
}

function storedState(state: SavedViewState): Record<string, unknown> {
  if (!state.query) {
    return { ...state };
  }

  return { ...state, query: withoutPage(state.query) };
}

function withoutPage(query: object): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(query).filter(([key]) => key !== "page" && key !== "after"),
  );
}

function savedOf(value: unknown): SavedViewRef {
  const row = recordOf(value, "saved view");

  return {
    id: textOf(row["id"]),
    rank: textOf(row["rank"]),
    fields: rowFields(row["fields"]),
  };
}

export function createSavedViews<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: SavedViewsOptions<S>): SavedViews<FieldsOf<S>> {
  type F = FieldsOf<S>;

  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "saved view fields",
  );

  const client: SavedViews<F> = {
    upsert: (input) => {
      const issues = savedViewIssues(input.state, options.lists?.[input.list]);

      if (issues.length > 0) {
        return AsyncResult.err(
          dbError("validation", "the saved view's state is not valid", {
            issues,
          }),
        );
      }

      return writeFields(fields, input.fields, (checked) =>
        call(
          "save_view",
          {
            tenant: input.organizationId,
            list: input.list,
            name: input.name,
            kind: input.kind ?? "table",
            scope: input.scope ?? "user",
            team: input.teamId ?? null,
            state: storedState(input.state),
            view_id: input.id ?? null,
            fields: checked,
          },
          savedOf,
        ),
      ).andThen((saved) => readFields(fields, saved));
    },
    list: ({ organizationId, list }) =>
      call("list_views", { tenant: organizationId, list }, (value) =>
        recordsOf(value, "list_views").map(viewOf),
      ).andThen((views) => readAllFields(fields, views)),
    reorder: ({ id, neighbors }) => {
      const key = rankBetweenResult(neighbors);

      if (!key.ok) {
        return AsyncResult.err(key.error);
      }

      return call("rank_view", { view_id: id, rank: key.data }, () => key.data);
    },
    setDefault: ({ id, on = true }) =>
      call(
        "set_default_view",
        { view_id: id, on_default: on },
        (value) => value === true,
      ),
    setPreference: ({ id, preference }) =>
      call(
        "set_view_preference",
        {
          view_id: id,
          make_default: preference.isDefault ?? null,
          hide: preference.hidden ?? null,
          pin: preference.pinned ?? null,
        },
        preferenceOf,
      ),
    duplicate: ({ id, input = {} }) =>
      call(
        "duplicate_view",
        {
          view_id: id,
          scope: input.scope ?? "user",
          name: input.name ?? null,
          team: input.teamId ?? null,
        },
        savedOf,
      ).andThen((saved) => readFields(fields, saved)),
    delete: (id) =>
      call("delete_view", { view_id: id }, (value) => value === true),
  };

  return withBlockHooks(client, options.hooks, {
    block: "saved-views",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

/** The fields of a view `defaultView` reads; `SavedView` fits. */
export interface DefaultViewCandidate {
  readonly scope: SavedViewScope;
  readonly isDefault: boolean;
  readonly preference?: Partial<
    Pick<SavedViewPreference, "isDefault" | "hidden">
  >;
}

/**
 * The view that opens first: the caller's preferred default, then the user's
 * slot default, a team default, the tenant's, then the first view. Views the
 * caller hid are skipped.
 */
export function defaultView<V extends DefaultViewCandidate>(
  views: readonly V[],
): V | undefined {
  const shown = views.filter((view) => view.preference?.hidden !== true);
  const preferred = shown.find((view) => view.preference?.isDefault === true);

  if (preferred) {
    return preferred;
  }

  for (const scope of SAVED_VIEW_SCOPES) {
    const match = shown.find((view) => view.isDefault && view.scope === scope);

    if (match) {
      return match;
    }
  }

  return shown[0];
}
