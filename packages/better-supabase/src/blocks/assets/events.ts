import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/**
 * `asset_location.created`, `asset_location.updated` and
 * `asset_location.archived`.
 */
export interface AssetLocationEventData {
  readonly organizationId: string;
  /** The location. */
  readonly id: string;
  /** `site`, `building`, `unit`, or the app's own kind. */
  readonly kind: string;
  readonly name: string;
  readonly parentId: string | null;
}

/** `asset.created`, `asset.updated`, `asset.assigned` and `asset.released`. */
export interface AssetEventData {
  readonly organizationId: string;
  /** The asset. */
  readonly id: string;
  readonly kind: string;
  readonly name: string;
  /** `active`, `maintenance` or `retired`. */
  readonly status: string;
  readonly locationId: string | null;
  /** `member` or a record type such as `party`, while assigned. */
  readonly assigneeType: string | null;
  readonly assigneeId: string | null;
}

/** `asset.depreciated`: one month of an asset's depreciation was booked. */
export interface AssetDepreciatedEventData {
  readonly organizationId: string;
  /** The depreciation row. */
  readonly id: string;
  readonly assetId: string;
  /** The first day of the month, `YYYY-MM-DD`. */
  readonly periodStart: string;
  /** Minor units, as text. */
  readonly amount: string;
  readonly currency: string;
  /** The accounting entry, when accounting books it. */
  readonly entryId: string | null;
}

/** `asset.disposed`: an asset was taken off the books. */
export interface AssetDisposedEventData {
  readonly organizationId: string;
  /** The asset. */
  readonly id: string;
  /** `YYYY-MM-DD`. */
  readonly disposedOn: string;
  /** The proceeds in minor units, as text. */
  readonly amount: string;
  readonly currency: string | null;
  /** The accounting entry, when accounting books it. */
  readonly entryId: string | null;
}

/** The events of the `assets` block: type to data. */
export type AssetsEvents = {
  readonly "asset_location.created": AssetLocationEventData;
  readonly "asset_location.updated": AssetLocationEventData;
  readonly "asset_location.archived": AssetLocationEventData;
  readonly "asset.created": AssetEventData;
  readonly "asset.updated": AssetEventData;
  readonly "asset.assigned": AssetEventData;
  readonly "asset.released": AssetEventData;
  readonly "asset.depreciated": AssetDepreciatedEventData;
  readonly "asset.disposed": AssetDisposedEventData;
};

/** The `assets` block's event types, for its manifest and `onBlockEvent`. */
export const assetsEvents: Events<AssetsEvents> = defineEvents({
  "asset_location.created": event<AssetLocationEventData>(),
  "asset_location.updated": event<AssetLocationEventData>(),
  "asset_location.archived": event<AssetLocationEventData>(),
  "asset.created": event<AssetEventData>(),
  "asset.updated": event<AssetEventData>(),
  "asset.assigned": event<AssetEventData>(),
  "asset.released": event<AssetEventData>(),
  "asset.depreciated": event<AssetDepreciatedEventData>(),
  "asset.disposed": event<AssetDisposedEventData>(),
});
