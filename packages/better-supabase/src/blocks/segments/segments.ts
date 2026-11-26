import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  CountOptions,
  FacetOptions,
  RequiredTenantOption,
} from "../../core/entity-list.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { FilterQuery } from "../../list/filter-query.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  entityList,
  foundOrNotFound,
  tenantOrOption,
} from "../../core/entity-list.ts";
import { conditionsOf } from "../automations/automations.ts";
import {
  applyTemporal,
  blockCall,
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { segmentListSurface } from "./lists.ts";

/** A saved filter over one subject type, with its materialized members. */
export interface Segment {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly description: string | undefined;
  /** A type in `config.recordTypes`, such as `company` or `deal`. */
  readonly subjectType: string;
  /** The filter tree over the subject type's rule fields. */
  readonly conditions: FilterQuery;
  /** The records that matched at the last refresh. */
  readonly memberCount: number;
  /**
   * When the members were last evaluated, or undefined before the first
   * refresh.
   */
  readonly refreshedAt: Temporal.Instant | undefined;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** What `upsert` takes. Leave `id` out to create a segment. */
export interface SegmentInput {
  readonly id?: string;
  /** Required to create; a segment's subject type can't change. */
  readonly subjectType?: string;
  readonly name?: string;
  readonly description?: string | null;
  readonly conditions?: FilterQuery;
}

/** A record in a segment. */
export interface SegmentMember {
  readonly subjectId: string;
  readonly enteredAt: Temporal.Instant;
}

/** A segment a record is in. */
export interface SegmentMembership {
  readonly segmentId: string;
  readonly name: string;
  readonly enteredAt: Temporal.Instant;
}

/** What a refresh changed. */
export interface SegmentRefresh {
  readonly entered: number;
  readonly left: number;
  readonly memberCount: number;
}

/** What `refreshDue` did. */
export interface SegmentRefreshReport {
  readonly segments: number;
  readonly entered: number;
  readonly left: number;
}

export interface Segments {
  /** Creates or changes a segment. Changing its conditions marks it due. */
  upsert(input: {
    organizationId: string;
    segment: SegmentInput;
  }): AsyncResult<Segment>;
  /** Deletes a segment and its members. False when there was none. */
  remove(segmentId: string): AsyncResult<boolean>;
  /**
   * By name.
   *
   * @deprecated Use `page`, which pages by keyset and takes `q`, sorts, array
   * filters and a count (ADR 1077).
   */
  list(
    input: { organizationId: string } & { readonly subjectType?: string },
  ): AsyncResult<Segment[]>;
  /**
   * One keyset page of the organization's segments, by name. Needs
   * `segments.read`. `filters` takes `subjectType` as a list; `q` searches the
   * name and description.
   */
  page(
    options: PageOptions & RequiredTenantOption,
  ): AsyncResult<ListPage<Segment>>;
  /** The values of each facet (`subjectType`) and how many segments hold each. */
  facets(
    options: FacetOptions & RequiredTenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many segments match the page's filters. */
  count(options: CountOptions & RequiredTenantOption): AsyncResult<Count>;
  /**
   * One segment, or undefined when there is none.
   *
   * @deprecated Use `getSegment`, which returns a `not_found` error for an
   * unknown id (ADR 1077).
   */
  get(segmentId: string): AsyncResult<Segment | undefined>;
  /** One segment by id, or a `not_found` error. */
  getSegment(segmentId: string): AsyncResult<Segment>;
  /**
   * A page of members, newest first; `after` is the last page's oldest
   * `enteredAt`.
   */
  members(
    input: { segmentId: string } & {
      readonly after?: Temporal.Instant;
      readonly limit?: number;
    },
  ): AsyncResult<SegmentMember[]>;
  /** The segments a record is in. */
  of(subject: {
    readonly type: string;
    readonly id: string;
  }): AsyncResult<SegmentMembership[]>;
  /** Evaluates a segment now and stores who entered and left. */
  refresh(segmentId: string): AsyncResult<SegmentRefresh>;
  /** Refreshes the segments not refreshed within `staleAfter`. Service role. */
  refreshDue(options?: {
    /** At most this many segments. Default: 25. */
    readonly segments?: number;
    /** A Postgres interval. Default: `1 hour`. */
    readonly staleAfter?: string;
  }): AsyncResult<SegmentRefreshReport>;
}

export interface SegmentsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Segments>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

function segmentOf(value: unknown): Segment {
  const row = recordOf(value, "segment");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    description: optionalText(row["description"]),
    subjectType: textOf(row["subjectType"]),
    conditions: conditionsOf(row["conditions"]),
    memberCount: Number(row["memberCount"]),
    refreshedAt: optionalInstant(row["refreshedAt"]),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

export function createSegments(options: SegmentsOptions): Segments {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const segments = entityList<Segment, RequiredTenantOption>({
    entity: "segment",
    surface: segmentListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "page_segments",
    rowOf: (row) => segmentOf(row),
  });

  const client: Segments = {
    upsert: ({ organizationId, segment }) =>
      call("upsert_segment", { tenant: organizationId, segment }, segmentOf),
    remove: (segmentId) =>
      call("delete_segment", { segment: segmentId }, (value) => value === true),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
    list: ({ organizationId, ...list }) =>
      call(
        "segments_list",
        { tenant: organizationId, subject_type: list.subjectType ?? null },
        (value) => recordsOf(value, "segments_list").map(segmentOf),
      ),
    page: segments.page,
    facets: segments.facets,
    count: segments.count,
    getSegment: (segmentId) =>
      call("segment_get", { segment: segmentId }, (value) =>
        value === null || value === undefined ? undefined : segmentOf(value),
      ).andThen((row) => foundOrNotFound("segment", row, segmentId)),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
    get: (segmentId) =>
      call("segment_get", { segment: segmentId }, (value) =>
        value === null || value === undefined ? undefined : segmentOf(value),
      ),
    members: ({ segmentId, ...page }) =>
      call(
        "list_segment_members",
        {
          segment: segmentId,
          after: instantArg(page.after) ?? null,
          max_count: page.limit ?? null,
        },
        (value) =>
          recordsOf(value, "list_segment_members").map((row) => ({
            subjectId: textOf(row["subjectId"]),
            enteredAt: requiredInstant(row["enteredAt"], "enteredAt"),
          })),
      ),
    of: (subject) =>
      call(
        "segments_of",
        { subject_type: subject.type, subject_id: subject.id },
        (value) =>
          recordsOf(value, "segments_of").map((row) => ({
            segmentId: textOf(row["id"]),
            name: textOf(row["name"]),
            enteredAt: requiredInstant(row["enteredAt"], "enteredAt"),
          })),
      ),
    refresh: (segmentId) =>
      call("refresh_segment", { segment: segmentId }, (value) => {
        const row = recordOf(value, "refresh_segment");

        return {
          entered: Number(row["entered"]),
          left: Number(row["left"]),
          memberCount: Number(row["memberCount"]),
        };
      }),
    refreshDue: (run = {}) =>
      call(
        "refresh_due_segments",
        {
          max_count: run.segments ?? null,
          stale_after: run.staleAfter ?? null,
        },
        (value) => {
          const row = recordOf(value, "refresh_due_segments");

          return {
            segments: Number(row["segments"]),
            entered: Number(row["entered"]),
            left: Number(row["left"]),
          };
        },
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "segments",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
