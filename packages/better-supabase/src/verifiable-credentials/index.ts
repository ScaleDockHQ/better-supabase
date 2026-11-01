export {
  CredentialError,
  signerFromJwk,
  signerFromSigningKeys,
  type CredentialSigner,
  type SigningKeysSigner,
} from "./shared.ts";

export {
  KEY_BINDING_TYP,
  SD_JWT_VC_TYP,
  issueSdJwt,
  parseSdJwt,
  presentSdJwt,
  verifySdJwt,
  type Disclosure,
  type IssueSdJwtOptions,
  type KeyBindingOptions,
  type ParsedSdJwt,
  type PresentSdJwtOptions,
  type StatusReference,
  type VerifiedSdJwt,
  type VerifySdJwtOptions,
} from "./sd-jwt.ts";

export {
  VC_JWT_TYP,
  issueJwtVc,
  verifyJwtVc,
  type IssueJwtVcOptions,
  type VerifiedJwtVc,
} from "./jwt-vc.ts";

export {
  BITSTRING_MIN_ENTRIES,
  STATUS_LIST_TYP,
  StatusList,
  VC_CONTEXT_V2,
  bitstringEntry,
  readBitstringStatus,
  readStatus,
  signBitstringStatusListCredential,
  signStatusListToken,
  type BitstringListCredentialOptions,
  type BitstringStatusEntry,
  type ReadStatusOptions,
  type StatusBit,
  type StatusListTokenOptions,
} from "./status-list.ts";

export {
  PRE_AUTHORIZED_GRANT,
  PROOF_TYP,
  createCredentialIssuer,
  memoryIssuanceStore,
  toResponse,
  type CreateOfferOptions,
  type CredentialConfiguration,
  type CredentialIssuer,
  type CredentialIssuerOptions,
  type CredentialOffer,
  type CredentialSource,
  type EndpointResult,
  type Grant,
  type IssuanceStore,
  type IssuedCredential,
  type PendingOffer,
} from "./openid4vci.ts";

export {
  createPresentationRequest,
  dcqlQuery,
  verifyPresentationResponse,
  type CreatedPresentationRequest,
  type CredentialQuery,
  type IssuerKeys,
  type PresentationOutcome,
  type PresentationRequest,
  type PresentationRequestOptions,
  type PresentationResponse,
  type VerifiedPresentation,
  type VerifyPresentationOptions,
} from "./openid4vp.ts";

export {
  courseCompletionSource,
  defineCredentialSource,
  passSource,
  qualificationSource,
  type CourseCompletionFact,
  type PassFact,
  type QualificationFact,
} from "./sources.ts";
