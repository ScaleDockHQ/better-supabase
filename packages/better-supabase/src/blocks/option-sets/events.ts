import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What the `option_set.*` events carry. */
export interface OptionSetEventData {
  readonly organizationId: string;
  readonly optionSetId: string;
  readonly subjectType: string;
  readonly field: string;
  readonly key: string;
}

/** What `option_set_item.created` and `option_set_item.updated` carry. */
export interface OptionSetItemEventData {
  readonly organizationId: string;
  readonly optionSetId: string;
  readonly itemId: string;
  readonly key: string;
  readonly level: number;
}

/** What `option_set_item.archived` carries. */
export interface OptionSetItemArchivedEventData {
  readonly organizationId: string;
  readonly optionSetId: string;
  readonly itemId: string;
}

/** The events of the `option-sets` block: type to data. */
export type OptionSetsEvents = {
  readonly "option_set.created": OptionSetEventData;
  readonly "option_set.updated": OptionSetEventData;
  readonly "option_set_item.created": OptionSetItemEventData;
  readonly "option_set_item.updated": OptionSetItemEventData;
  readonly "option_set_item.archived": OptionSetItemArchivedEventData;
  readonly "option_set_item.restored": OptionSetItemArchivedEventData;
};

/** The `option-sets` block's event types, for its manifest and `onBlockEvent`. */
export const optionSetsEvents: Events<OptionSetsEvents> = defineEvents({
  "option_set.created": event<OptionSetEventData>(),
  "option_set.updated": event<OptionSetEventData>(),
  "option_set_item.created": event<OptionSetItemEventData>(),
  "option_set_item.updated": event<OptionSetItemEventData>(),
  "option_set_item.archived": event<OptionSetItemArchivedEventData>(),
  "option_set_item.restored": event<OptionSetItemArchivedEventData>(),
});
