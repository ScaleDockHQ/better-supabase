export {
  createIncidents,
  type ComponentImpact,
  type ComponentStatus,
  type Incident,
  type IncidentChanges,
  type IncidentDetail,
  type IncidentImpact,
  type IncidentImpactInput,
  type IncidentInput,
  type IncidentListOptions,
  type Incidents,
  type IncidentSeverity,
  type IncidentsOptions,
  type IncidentStatus,
  type IncidentUpdate,
  type IncidentUpdateInput,
  type Postmortem,
  type PostmortemAction,
  type PostmortemActionInput,
  type PostmortemInput,
  type PostmortemStatus,
  type PublicIncident,
  type PublicStatusComponent,
  type PublicStatusPage,
  type PublicUptimeDay,
  type StatusComponent,
  type StatusComponentInput,
  type StatusPage,
  type StatusPageInput,
} from "./incidents.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../core/block-hooks.ts";

export type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport, RpcClient } from "../../core/block-transport.ts";

export { incidentsBlock } from "./manifest.ts";

export {
  incidentChangesSchema,
  incidentInputSchema,
  postmortemInputSchema,
  statusComponentInputSchema,
  statusPageInputSchema,
} from "./schemas.ts";

export { incidentsEvents } from "./events.ts";

export type {
  IncidentOpenedEventData,
  IncidentResolvedEventData,
  IncidentsEvents,
  IncidentUpdatedEventData,
  PostmortemPublishedEventData,
  StatusComponentChangedEventData,
} from "./events.ts";
