/**
 * Versions of evolving specs and conventions the code follows. Moving a pin is
 * a minor release with a changeset (see the standards docs page).
 */
export const SPEC_PINS: {
  readonly otelSemconv: "1.37.0";
  /** OTLP/HTTP JSON that the webhooks block's `otlpLogs()` encoder writes. */
  readonly otlp: "1.7.0";
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
  /** The PowerSync sync streams config edition `powersync streams` writes. */
  readonly powersyncSyncStreams: "3";
  readonly aiSdkUiMessageStream: "v1";
  readonly anthropicMemoryTool: "20250818";
  /** RFC 5545 recurrence rules expanded by the reminders block. */
  readonly rfc5545: "2009-09";
  /** RFC 4180 CSV read by `parseCsv` and written by `toCsv`. */
  readonly rfc4180: "2005-10";
  /**
   * ISO 4217 List One publication behind `better-supabase/commerce` minor
   * units.
   */
  readonly iso4217: "2026-09-17";
  /**
   * ISO 13616-1 edition behind the `iban` column and custom field format: the
   * electronic form and the mod 97 check digits.
   */
  readonly iso13616: "2020";
  /** ISO 20022 bank-to-customer statement versions `parseCamt053` reads. */
  readonly camt053v02: "camt.053.001.02";
  readonly camt053v08: "camt.053.001.08";
  /**
   * ISO 20022 customer credit transfer initiation `sepaCreditTransferXml`
   * writes.
   */
  readonly pain001v09: "pain.001.001.09";
  /** SWIFT MT940 customer statement layout `parseMt940` reads. */
  readonly mt940: "SR2025";
  /** ISO 11649 creditor references the banking block matches on. */
  readonly iso11649: "2009";
  /** FHIR R4 release whose base resources `better-supabase/fhir` maps to. */
  readonly fhirR4: "4.0.1";
  /**
   * OASIS UBL release whose Invoice and CreditNote
   * `better-supabase/e-invoicing` writes and reads.
   */
  readonly ubl: "2.1";
  /** The European e-invoicing semantic model `toUbl` follows. */
  readonly en16931: "EN 16931-1:2017";
  /** The Peppol BIS Billing release in the documents' specification identifier. */
  readonly peppolBisBilling: "3.0";
  /**
   * OECD Standard Audit File for Tax (SAF-T) schema that
   * `better-supabase/audit-files` reads and writes.
   */
  readonly saftOecd: "2.00";
  /**
   * Dutch audit file (XAF) release that `better-supabase/audit-files` reads and
   * writes.
   */
  readonly xaf: "3.2";
  /**
   * RFC 6902 JSON Patch that the versions block's `createPatch` writes and
   * `applyPatch` applies.
   */
  readonly rfc6902: "2013-04";
  /**
   * RFC 9396 `authorization_details` that delegated tokens and job envelopes
   * carry.
   */
  readonly rfc9396: "2023-05";
  /**
   * RFC 9864 fully specified JOSE algorithms; `Ed25519` is the alg the
   * signing-keys block can write instead of `EdDSA`.
   */
  readonly rfc9864: "2025-10";
  /**
   * RFC 8417 Security Event Tokens that the security-events block mints and
   * verifies.
   */
  readonly rfc8417: "2018-07";
  /**
   * RFC 8935 push delivery of SETs: the `set` webhook format and the receiver's
   * push endpoint.
   */
  readonly rfc8935: "2020-11";
  /**
   * RFC 8936 poll delivery of SETs that the transmitter serves and the receiver
   * runs.
   */
  readonly rfc8936: "2020-11";
  /**
   * OpenID Shared Signals Framework: metadata, streams, status and
   * verification.
   */
  readonly ssf: "1.0";
  /** OpenID CAEP event types in `CAEP_EVENTS`. */
  readonly caep: "1.0";
  /** OpenID RISC event types in `RISC_EVENTS`. */
  readonly risc: "1.0";
  /** RFC 9068 JWT access tokens that `accessTokenResolver` verifies. */
  readonly rfc9068: "2021-10";
  /** RFC 7591 client registration metadata the oauth-server block stores. */
  readonly rfc7591: "2015-07";
  /** RFC 7636 PKCE; the oauth-server block accepts only the S256 method. */
  readonly rfc7636: "2015-09";
  /**
   * RFC 8628 device authorization that the oauth-server block's device codes
   * follow.
   */
  readonly rfc8628: "2019-08";
  /**
   * RFC 9700 OAuth security best current practice behind code reuse and
   * redirect URI rules.
   */
  readonly rfc9700: "2025-01";
  /**
   * Draft-ietf-httpapi-ratelimit-headers revision behind `rateLimitHeader` and
   * the Hono and oRPC `rateLimit()`.
   */
  readonly ratelimitHeaders: "draft-11";
  /**
   * The shadcn release whose registry schemas the `@better-supabase` items
   * follow.
   */
  readonly shadcnRegistry: "4.21.4";
  /** IMS LTI 1.3 core, the launch `verifyLtiLaunch` checks. */
  readonly lti: "1.3";
  /** IEEE 9274.1.1 xAPI, the statements the courses block writes. */
  readonly xapi: "2.0.0";
  /** 1EdTech Open Badges, the credential the courses export writes. */
  readonly openBadges: "3.0.3";
  /** HL7 SMART App Launch, the launch `createSmartLaunch` runs. */
  readonly smartAppLaunch: "2.2.0";
  /** HL7 CDS Hooks, the service API `createCdsHooksServer` serves. */
  readonly cdsHooks: "2.0";
  /** Berlin Group NextGenPSD2 XS2A framework, read by `berlinGroupFeed`. */
  readonly berlinGroupXs2a: "1.3.12";
  /** C2PA technical specification, the manifest a `C2paReader` reports on. */
  readonly c2pa: "2.2";
  /** W3C ODRL Information Model, the policy the DAM exports. */
  readonly odrl: "2.2";
  /** Sitemaps.org protocol, the sitemaps the content block writes. */
  readonly sitemaps: "0.9";
  /**
   * RFC 9309 Robots Exclusion Protocol, the `robots.txt` the content block
   * writes.
   */
  readonly rfc9309: "2022-09";
  /** W3C JSON-LD, the structured data the content block writes. */
  readonly jsonLd: "1.1";
  /**
   * The TypeScript 7.1 content mapper protocol version (7.1.0-beta) that
   * `better-supabase/mapper` speaks.
   */
  readonly typescriptContentMapper: "1";
} = {
  otelSemconv: "1.37.0",
  otlp: "1.7.0",
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
  powersyncSyncStreams: "3",
  aiSdkUiMessageStream: "v1",
  anthropicMemoryTool: "20250818",
  rfc5545: "2009-09",
  rfc4180: "2005-10",
  iso4217: "2026-09-17",
  iso13616: "2020",
  camt053v02: "camt.053.001.02",
  camt053v08: "camt.053.001.08",
  pain001v09: "pain.001.001.09",
  mt940: "SR2025",
  iso11649: "2009",
  fhirR4: "4.0.1",
  ubl: "2.1",
  en16931: "EN 16931-1:2017",
  peppolBisBilling: "3.0",
  saftOecd: "2.00",
  xaf: "3.2",
  rfc6902: "2013-04",
  rfc9396: "2023-05",
  rfc9864: "2025-10",
  rfc8417: "2018-07",
  rfc8935: "2020-11",
  rfc8936: "2020-11",
  ssf: "1.0",
  caep: "1.0",
  risc: "1.0",
  rfc9068: "2021-10",
  rfc7591: "2015-07",
  rfc7636: "2015-09",
  rfc8628: "2019-08",
  rfc9700: "2025-01",
  ratelimitHeaders: "draft-11",
  shadcnRegistry: "4.21.4",
  lti: "1.3",
  xapi: "2.0.0",
  openBadges: "3.0.3",
  smartAppLaunch: "2.2.0",
  cdsHooks: "2.0",
  berlinGroupXs2a: "1.3.12",
  c2pa: "2.2",
  odrl: "2.2",
  sitemaps: "0.9",
  rfc9309: "2022-09",
  jsonLd: "1.1",
  typescriptContentMapper: "1",
};
