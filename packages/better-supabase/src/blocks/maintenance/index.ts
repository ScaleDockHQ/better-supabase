export {
  createMaintenance,
  type Maintenance,
  type MaintenanceCalibration,
  type MaintenanceCalibrationInput,
  type MaintenanceCalibrationListOptions,
  type MaintenanceCalibrationResult,
  type MaintenanceGenerated,
  type MaintenanceMeter,
  type MaintenanceOptions,
  type MaintenancePart,
  type MaintenancePlan,
  type MaintenancePlanChange,
  type MaintenancePlanInput,
  type MaintenancePlanKind,
  type MaintenancePlanListOptions,
  type MaintenancePlanStatus,
  type MaintenancePriority,
} from "./maintenance.ts";

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

export { maintenanceBlock } from "./manifest.ts";

export {
  maintenanceCalibrationInputSchema,
  maintenancePlanInputSchema,
} from "./schemas.ts";

export { maintenanceEvents } from "./events.ts";

export type {
  MaintenanceCalibrationEventData,
  MaintenanceEvents,
  MaintenanceMeterReadingEventData,
  MaintenancePlanEventData,
  MaintenancePlanWorkOrderEventData,
} from "./events.ts";

export {
  createTelemetryHandler,
  ingestTelemetry,
  parseOtlpMetrics,
  parseTelemetryPoints,
  type TelemetryFailure,
  type TelemetryHandlerOptions,
  type TelemetryIngestOptions,
  type TelemetryPoint,
  type TelemetrySummary,
} from "./telemetry.ts";
