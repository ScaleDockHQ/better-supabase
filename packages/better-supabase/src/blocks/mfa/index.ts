export {
  createMfaController,
  createStepUpController,
  needsStepUp,
  type MfaActions,
  type MfaApi,
  type MfaAssurance,
  type MfaController,
  type MfaControllerOptions,
  type MfaEnrollment,
  type MfaFactor,
  type PasskeyOptions,
  type MfaSnapshot,
  type RawMfaFactor,
  type StepUpActions,
  type StepUpController,
  type StepUpControllerOptions,
  type StepUpSnapshot,
  type WebAuthnApi,
} from "./client.ts";

export { mfaBlock } from "./manifest.ts";
