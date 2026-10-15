/**
 * Versions of evolving specs and conventions the code follows. Moving a pin
 * is a minor release with a changeset (see the standards docs page).
 */
export const SPEC_PINS: {
  readonly otelSemconv: "1.37.0";
  readonly mcp: "2026-07-28";
  /** The default OpenAPI version `createOpenApi` emits. */
  readonly openapi: "3.1.2";
  readonly openapi30: "3.0.4";
  readonly openapi31: "3.1.2";
  readonly openapi32: "3.2.1";
  /** `src/oas.md` on the `v3.3-dev` branch of OAI/OpenAPI-Specification. */
  readonly openapi33Preview: "aa2f6c0";
  /** OAI sig-security discussion #50, as of this date. */
  readonly securityProfiles: "sig-security#50@2026-05-05";
  readonly overlay10: "1.0.0";
  readonly overlay11: "1.1.0";
  readonly overlay12: "1.2.0";
  readonly arazzo10: "1.0.1";
  readonly arazzo11: "1.1.0";
  readonly asyncapi30: "3.0.0";
  readonly asyncapi31: "3.1.0";
  /** OpenID AuthZEN Authorization API, the vocabulary of `Authorizer`. */
  readonly authzen: "1.0";
  readonly cloudevents: "1.0.2";
  readonly standardWebhooks: "1.0.0";
  readonly sarif: "2.1.0";
  readonly jsonSchema: "2020-12";
  readonly postgrestAggregates: "12";
  readonly serverTiming: "WD-20260407";
  readonly stripeSyncEngine: "0.48.5";
  readonly pgvector: "0.8";
  readonly ocsf: "1.9.0";
  readonly openfeature: "0.9.0";
  readonly scim: "2.0";
  readonly supabaseSdkCapabilities: "1.14.0";
  readonly aiMessage: "1";
  readonly aiSdkUiMessageStream: "v1";
  readonly anthropicMemoryTool: "20250818";
  /** RFC 5545 recurrence rules expanded by the reminders block. */
  readonly rfc5545: "2009-09";
  /** RFC 4180 CSV read by `parseCsv` and written by `toCsv`. */
  readonly rfc4180: "2005-10";
  /** ISO 4217 List One publication behind the commerce block's minor units. */
  readonly iso4217: "2026-09-17";
  /** RFC 6902 JSON Patch that the versions block's `createPatch` writes and `applyPatch` applies. */
  readonly rfc6902: "2013-04";
  /** RFC 9396 `authorization_details` that delegated tokens and job envelopes carry. */
  readonly rfc9396: "2023-05";
  /** The shadcn release whose registry schemas the `@better-supabase` items follow. */
  readonly shadcnRegistry: "4.21.4";
} = {
  otelSemconv: "1.37.0",
  mcp: "2026-07-28",
  openapi: "3.1.2",
  openapi30: "3.0.4",
  openapi31: "3.1.2",
  openapi32: "3.2.1",
  openapi33Preview: "aa2f6c0",
  securityProfiles: "sig-security#50@2026-05-05",
  overlay10: "1.0.0",
  overlay11: "1.1.0",
  overlay12: "1.2.0",
  arazzo10: "1.0.1",
  arazzo11: "1.1.0",
  asyncapi30: "3.0.0",
  asyncapi31: "3.1.0",
  authzen: "1.0",
  cloudevents: "1.0.2",
  standardWebhooks: "1.0.0",
  sarif: "2.1.0",
  jsonSchema: "2020-12",
  postgrestAggregates: "12",
  serverTiming: "WD-20260407",
  stripeSyncEngine: "0.48.5",
  pgvector: "0.8",
  ocsf: "1.9.0",
  openfeature: "0.9.0",
  scim: "2.0",
  supabaseSdkCapabilities: "1.14.0",
  aiMessage: "1",
  aiSdkUiMessageStream: "v1",
  anthropicMemoryTool: "20250818",
  rfc5545: "2009-09",
  rfc4180: "2005-10",
  iso4217: "2026-09-17",
  rfc6902: "2013-04",
  rfc9396: "2023-05",
  shadcnRegistry: "4.21.4",
};
