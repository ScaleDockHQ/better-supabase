import type { ForecastSnapshotEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `forecasts` block: type to data. */
export type ForecastsEvents = {
  readonly "forecast.snapshotted": ForecastSnapshotEventData;
};

/** The `forecasts` block's event types, for its manifest and `onBlockEvent`. */
export const forecastsEvents: Events<ForecastsEvents> = defineEvents({
  "forecast.snapshotted": event<ForecastSnapshotEventData>(),
});
