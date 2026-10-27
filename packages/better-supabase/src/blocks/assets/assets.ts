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
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface AssetsOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Assets>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** A point in WGS 84 degrees. */
export interface GeoPoint {
  readonly latitude: number;
  readonly longitude: number;
}

/** A GeoJSON Polygon or MultiPolygon, for a location's area. */
export type GeoArea = Readonly<Record<string, unknown>>;

/** A place in the hierarchy: a site, building, floor, unit or room. */
export interface AssetLocation {
  readonly id: string;
  readonly organizationId: string;
  readonly parentId?: string;
  readonly kind: string;
  readonly name: string;
  /** Unique in the organization. */
  readonly code?: string;
  readonly address: Readonly<Record<string, unknown>>;
  readonly point?: GeoPoint;
  /** The outline as GeoJSON, with the `postgis` option. */
  readonly area?: GeoArea;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** One step of a location's path from the top. */
export interface AssetLocationStep {
  readonly id: string;
  readonly kind: string;
  readonly name: string;
}

export interface AssetLocationDetail extends AssetLocation {
  /** From the top down to this location. */
  readonly path: readonly AssetLocationStep[];
  /** Open sublocations. */
  readonly locations: number;
  /** Assets in service at this location. */
  readonly assets: number;
}

export interface AssetLocationInput {
  readonly kind: string;
  readonly name: string;
  readonly parentId?: string;
  readonly code?: string;
  readonly address?: Readonly<Record<string, unknown>>;
  readonly point?: GeoPoint;
  /** Needs the `postgis` option. */
  readonly area?: GeoArea;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

/** What to change; `null` clears an optional field. */
export interface AssetLocationPatch {
  readonly kind?: string;
  readonly name?: string;
  readonly parentId?: string | null;
  readonly code?: string | null;
  readonly address?: Readonly<Record<string, unknown>> | null;
  readonly point?: GeoPoint | null;
  readonly area?: GeoArea | null;
  readonly metadata?: Readonly<Record<string, unknown>> | null;
}

export type AssetStatus = "active" | "maintenance" | "retired";

/** Who or what holds an asset: `member` (a user id) or a record. */
export interface AssetAssignee {
  readonly type: string;
  readonly id: string;
}

export interface Asset {
  readonly id: string;
  readonly organizationId: string;
  readonly locationId?: string;
  readonly kind: string;
  readonly name: string;
  /** The asset tag, unique in the organization. */
  readonly tag?: string;
  readonly serialNumber?: string;
  readonly status: AssetStatus;
  readonly assignee?: AssetAssignee;
  /** Where a moving asset was last seen. */
  readonly point?: GeoPoint;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly retiredAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** The records that name an asset, when their blocks are installed. */
export interface AssetLinks {
  readonly bookingResources: readonly {
    readonly id: string;
    readonly name: string;
  }[];
  /** Open work items, newest first, at most 50. */
  readonly workItems: readonly {
    readonly id: string;
    readonly title: string;
  }[];
}

export interface AssetDetail extends Asset {
  readonly locationPath: readonly AssetLocationStep[];
  readonly links: AssetLinks;
}

export interface AssetInput {
  readonly kind: string;
  readonly name: string;
  readonly locationId?: string;
  readonly tag?: string;
  readonly serialNumber?: string;
  readonly point?: GeoPoint;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

/** What to change; `null` clears an optional field. Retiring releases it. */
export interface AssetPatch {
  readonly kind?: string;
  readonly name?: string;
  readonly locationId?: string | null;
  readonly tag?: string | null;
  readonly serialNumber?: string | null;
  readonly status?: AssetStatus;
  readonly point?: GeoPoint | null;
  readonly metadata?: Readonly<Record<string, unknown>> | null;
}

export interface AssetListOptions {
  readonly locationId?: string;
  /** With `locationId`, also the assets below it. */
  readonly includeSublocations?: boolean;
  readonly kind?: string;
  readonly status?: AssetStatus;
  readonly assignee?: AssetAssignee;
  /** Part of the name, or an exact tag or serial number. */
  readonly query?: string;
  /** Pages back from an asset's `createdAt`. */
  readonly before?: Temporal.Instant;
  readonly pageSize?: number;
}

export interface AssetAssignment {
  readonly id: string;
  readonly assetId: string;
  readonly assignee: AssetAssignee;
  readonly note?: string;
  readonly assignedBy?: string;
  readonly assignedAt: Temporal.Instant;
  readonly releasedAt?: Temporal.Instant;
}

export interface AssetsNearOptions extends GeoPoint {
  /** Above 0, at most 1,000,000. */
  readonly radiusMeters: number;
  readonly kind?: string;
  readonly pageSize?: number;
}

/** What is near a point, nearest first. */
export interface AssetsNear {
  readonly assets: readonly (Asset & { readonly distanceMeters: number })[];
  readonly locations: readonly (AssetLocation & {
    readonly distanceMeters: number;
  })[];
}

/** A record that can name an asset. */
export interface AssetLinkTarget {
  readonly type: "booking_resource" | "work_item";
  readonly id: string;
}

export interface Assets {
  /** Needs `assets.manage`. */
  createLocation(input: AssetLocationInput): AsyncResult<AssetLocation>;
  updateLocation(
    locationId: string,
    patch: AssetLocationPatch,
  ): AsyncResult<AssetLocation>;
  /** Only a location without open sublocations or assets in service. */
  archiveLocation(locationId: string): AsyncResult<AssetLocation>;
  location(locationId: string): AsyncResult<AssetLocationDetail>;
  /** The locations under `parentId`, or the top ones. */
  locations(options?: {
    readonly parentId?: string;
    readonly includeArchived?: boolean;
    readonly pageSize?: number;
  }): AsyncResult<readonly AssetLocation[]>;
  /** Needs `assets.manage`. */
  createAsset(input: AssetInput): AsyncResult<Asset>;
  updateAsset(assetId: string, patch: AssetPatch): AsyncResult<Asset>;
  asset(assetId: string): AsyncResult<AssetDetail>;
  /** Newest first, in the block's tenant. */
  assets(options?: AssetListOptions): AsyncResult<readonly Asset[]>;
  /** The assets a member or a record holds. The record decides the tenant. */
  assignedTo(
    assignee: RecordRef | AssetAssignee,
    options?: { readonly pageSize?: number },
  ): AsyncResult<readonly Asset[]>;
  /** Needs `assets.assign`. Ends the previous assignment. */
  assign(
    assetId: string,
    assignee: AssetAssignee,
    options?: { readonly note?: string },
  ): AsyncResult<Asset>;
  release(assetId: string): AsyncResult<Asset>;
  assignments(
    assetId: string,
    options?: { readonly pageSize?: number },
  ): AsyncResult<readonly AssetAssignment[]>;
  /** Assets and locations within a radius, in the block's tenant. */
  near(options: AssetsNearOptions): AsyncResult<AssetsNear>;
  /** Locations whose area contains a point. Needs the `postgis` option. */
  locationsAt(point: GeoPoint): AsyncResult<readonly AssetLocation[]>;
  /** Names (or with `null`, clears) the asset a record is about. */
  link(
    target: AssetLinkTarget,
    assetId: string | null,
  ): AsyncResult<AssetLinkTarget & { readonly assetId: string | null }>;
}

const STATUSES: readonly AssetStatus[] = ["active", "maintenance", "retired"];

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const objectOf = (value: unknown): Readonly<Record<string, unknown>> =>
  isRecord(value) ? value : {};

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

function pointOf(row: Readonly<Record<string, unknown>>): GeoPoint | undefined {
  const latitude = numberOf(row["latitude"]);
  const longitude = numberOf(row["longitude"]);

  return latitude === undefined || longitude === undefined
    ? undefined
    : { latitude, longitude };
}

function stepsOf(value: unknown, fn: string): readonly AssetLocationStep[] {
  return recordsOf(value, fn).map((step) => ({
    id: textOf(step["id"]),
    kind: textOf(step["kind"]),
    name: textOf(step["name"]),
  }));
}

function locationOf(value: unknown, fn: string): AssetLocation {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    kind: textOf(row["kind"]),
    name: textOf(row["name"]),
    address: objectOf(row["address"]),
    metadata: objectOf(row["metadata"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("parentId", optionalText(row["parentId"])),
    ...optional("code", optionalText(row["code"])),
    ...optional("point", pointOf(row)),
    ...optional("area", isRecord(row["area"]) ? row["area"] : undefined),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
  };
}

function assetOf(value: unknown, fn: string): Asset {
  const row = recordOf(value, fn);
  const assigneeType = optionalText(row["assigneeType"]);
  const assigneeId = optionalText(row["assigneeId"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    kind: textOf(row["kind"]),
    name: textOf(row["name"]),
    status: enumOrThrow(row["status"], STATUSES, "asset status"),
    metadata: objectOf(row["metadata"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional(
      "assignee",
      assigneeType === undefined || assigneeId === undefined
        ? undefined
        : { type: assigneeType, id: assigneeId },
    ),
    ...optional("locationId", optionalText(row["locationId"])),
    ...optional("tag", optionalText(row["tag"])),
    ...optional("serialNumber", optionalText(row["serialNumber"])),
    ...optional("point", pointOf(row)),
    ...optional("retiredAt", optionalInstant(row["retiredAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function assignmentOf(value: unknown, fn: string): AssetAssignment {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    assetId: textOf(row["assetId"]),
    assignee: {
      type: textOf(row["assigneeType"]),
      id: textOf(row["assigneeId"]),
    },
    assignedAt: requiredInstant(row["assignedAt"], "assignedAt"),
    ...optional("note", optionalText(row["note"])),
    ...optional("assignedBy", optionalText(row["assignedBy"])),
    ...optional("releasedAt", optionalInstant(row["releasedAt"])),
  };
}

const distanceOf = (row: Readonly<Record<string, unknown>>): number =>
  Number(row["distanceMeters"] ?? 0);

/** The patch keys the SQL functions read, with a point split in two. */
function patchArg(
  patch: AssetLocationPatch | AssetPatch,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  const entries: [string, unknown][] = Object.entries(patch);

  for (const [key, value] of entries) {
    if (value === undefined) {
      continue;
    }

    if (key === "point") {
      const point = isRecord(value) ? value : {};
      out["latitude"] = point["latitude"] ?? null;
      out["longitude"] = point["longitude"] ?? null;
      continue;
    }

    out[key] = value;
  }

  return out;
}

/** The `assets` SQL module as typed calls. */
export function createAssets(options: AssetsOptions): Assets {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const list = (
    organizationId: string | null,
    filter: AssetListOptions,
  ): AsyncResult<readonly Asset[]> =>
    call(
      "list_assets",
      {
        tenant: organizationId,
        location_id: filter.locationId ?? null,
        include_sublocations: filter.includeSublocations ?? false,
        kind: filter.kind ?? null,
        status: filter.status ?? null,
        assignee_type: filter.assignee?.type ?? null,
        assignee_id: filter.assignee?.id ?? null,
        query: filter.query ?? null,
        before: instantArg(filter.before) ?? null,
        page_size: filter.pageSize ?? null,
      },
      (value) =>
        recordsOf(value, "list_assets").map((row) =>
          assetOf(row, "list_assets"),
        ),
    );

  const client: Assets = {
    createLocation: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_asset_location",
          {
            tenant: organizationId,
            kind: input.kind,
            name: input.name,
            parent_id: input.parentId ?? null,
            code: input.code ?? null,
            address: input.address ?? null,
            latitude: input.point?.latitude ?? null,
            longitude: input.point?.longitude ?? null,
            area: input.area ?? null,
            metadata: input.metadata ?? null,
          },
          (value) => locationOf(value, "create_asset_location"),
        ),
      ),
    updateLocation: (locationId, patch) =>
      call(
        "update_asset_location",
        { location_id: locationId, patch: patchArg(patch) },
        (value) => locationOf(value, "update_asset_location"),
      ),
    archiveLocation: (locationId) =>
      call("archive_asset_location", { location_id: locationId }, (value) =>
        locationOf(value, "archive_asset_location"),
      ),
    location: (locationId) =>
      call("get_asset_location", { location_id: locationId }, (value) => {
        const row = recordOf(value, "get_asset_location");

        return {
          ...locationOf(row, "get_asset_location"),
          path: stepsOf(row["path"], "get_asset_location"),
          locations: Number(row["locations"] ?? 0),
          assets: Number(row["assets"] ?? 0),
        };
      }),
    locations: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_asset_locations",
          {
            tenant: organizationId,
            parent_id: filter.parentId ?? null,
            include_archived: filter.includeArchived ?? false,
            page_size: filter.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "list_asset_locations").map((row) =>
              locationOf(row, "list_asset_locations"),
            ),
        ),
      ),
    createAsset: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_asset",
          {
            tenant: organizationId,
            kind: input.kind,
            name: input.name,
            location_id: input.locationId ?? null,
            tag: input.tag ?? null,
            serial_number: input.serialNumber ?? null,
            latitude: input.point?.latitude ?? null,
            longitude: input.point?.longitude ?? null,
            metadata: input.metadata ?? null,
          },
          (value) => assetOf(value, "create_asset"),
        ),
      ),
    updateAsset: (assetId, patch) =>
      call(
        "update_asset",
        { asset_id: assetId, patch: patchArg(patch) },
        (value) => assetOf(value, "update_asset"),
      ),
    asset: (assetId) =>
      call("get_asset", { asset_id: assetId }, (value) => {
        const row = recordOf(value, "get_asset");
        const links = objectOf(row["links"]);

        return {
          ...assetOf(row, "get_asset"),
          locationPath: stepsOf(row["locationPath"], "get_asset"),
          links: {
            bookingResources: recordsOf(
              links["bookingResources"] ?? [],
              "get_asset",
            ).map((link) => ({
              id: textOf(link["id"]),
              name: textOf(link["name"]),
            })),
            workItems: recordsOf(links["workItems"] ?? [], "get_asset").map(
              (link) => ({
                id: textOf(link["id"]),
                title: textOf(link["title"]),
              }),
            ),
          },
        };
      }),
    assets: (filter = {}) =>
      tenant().andThen((organizationId) => list(organizationId, filter)),
    assignedTo: (assignee, filter = {}) =>
      list(null, {
        assignee: { type: assignee.type, id: assignee.id },
        ...optional("pageSize", filter.pageSize),
      }),
    assign: (assetId, assignee, assign = {}) =>
      call(
        "assign_asset",
        {
          asset_id: assetId,
          assignee_type: assignee.type,
          assignee_id: assignee.id,
          note: assign.note ?? null,
        },
        (value) => assetOf(value, "assign_asset"),
      ),
    release: (assetId) =>
      call("release_asset", { asset_id: assetId }, (value) =>
        assetOf(value, "release_asset"),
      ),
    assignments: (assetId, filter = {}) =>
      call(
        "asset_assignment_history",
        { asset_id: assetId, page_size: filter.pageSize ?? null },
        (value) =>
          recordsOf(value, "asset_assignment_history").map((row) =>
            assignmentOf(row, "asset_assignment_history"),
          ),
      ),
    near: (near) =>
      tenant().andThen((organizationId) =>
        call(
          "assets_near",
          {
            tenant: organizationId,
            latitude: near.latitude,
            longitude: near.longitude,
            radius_meters: near.radiusMeters,
            kind: near.kind ?? null,
            page_size: near.pageSize ?? null,
          },
          (value) => {
            const row = recordOf(value, "assets_near");

            return {
              assets: recordsOf(row["assets"], "assets_near").map((item) => ({
                ...assetOf(item, "assets_near"),
                distanceMeters: distanceOf(item),
              })),
              locations: recordsOf(row["locations"], "assets_near").map(
                (item) => ({
                  ...locationOf(item, "assets_near"),
                  distanceMeters: distanceOf(item),
                }),
              ),
            };
          },
        ),
      ),
    locationsAt: (point) =>
      tenant().andThen((organizationId) =>
        call(
          "asset_locations_at",
          {
            tenant: organizationId,
            latitude: point.latitude,
            longitude: point.longitude,
          },
          (value) =>
            recordsOf(value, "asset_locations_at").map((row) =>
              locationOf(row, "asset_locations_at"),
            ),
        ),
      ),
    link: (target, assetId) =>
      call(
        "set_asset_link",
        { target_type: target.type, target_id: target.id, asset_id: assetId },
        () => ({ type: target.type, id: target.id, assetId }),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "assets",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
