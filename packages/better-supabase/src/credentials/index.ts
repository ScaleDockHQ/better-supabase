export {
  credentialRouter,
  revokeIfConfigured,
  type RevokeIfConfiguredOptions,
} from "./compose.ts";
export {
  credentialRefInTenant,
  foreignCredentialRef,
  subjectFor,
  tenantCredentialRef,
  type CompleteAuthorizationOptions,
  type CredentialCapabilities,
  type CredentialProvider,
  type CredentialRef,
  type CredentialSubject,
  type CredentialToken,
  type GetTokenOptions,
  type SetCredentialOptions,
  type StartAuthorizationOptions,
} from "./provider.ts";
export {
  vaultCredentials,
  type VaultCredentialRef,
  type VaultCredentials,
  type VaultCredentialsOptions,
  type VaultInboundScheme,
} from "./vault.ts";
export { rpcTransport, sqlTransport } from "../core/block-transport.ts";
export type { BlockTransport } from "../core/block-transport.ts";
