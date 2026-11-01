export {
  CARE_BUILT_IN_SOURCE,
  createClinicalDecisionSupport,
  type CareAlert,
  type CareAlertDecision,
  type CareAlertKind,
  type CareAlertListOptions,
  type CareAlertSeverity,
  type CareAlertStatus,
  type CareDecisionAlert,
  type CareDecisionConsent,
  type CareDecisionContext,
  type CareDecisionMedication,
  type CareDecisionObservation,
  type CareDecisionPlan,
  type CareDecisionRequest,
  type CareRule,
  type CareRuleInput,
  type CareRuleKind,
  type ClinicalDecisionSupport,
  type ClinicalDecisionSupportClient,
  type ClinicalDecisionSupportOptions,
} from "./clinical-decision-support.ts";

export {
  clinicalDecisionSupportEvents,
  type CareAlertEventData,
  type CareRuleEventData,
  type ClinicalDecisionSupportEvents,
} from "./events.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../core/block-hooks.ts";

export type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export { clinicalDecisionSupportBlock } from "./manifest.ts";

export { careRuleInputSchema } from "./schemas.ts";
