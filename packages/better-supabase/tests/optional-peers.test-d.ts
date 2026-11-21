// oxlint-disable-next-line eslint/no-restricted-imports -- anthropicMemory takes the provider's tools, so the test needs their real type.
import type { anthropic } from "@ai-sdk/anthropic";
// oxlint-disable-next-line eslint/no-restricted-imports -- vercelSandboxes types the session adapter structurally; the test checks it against the real one.
import type * as SandboxSessions from "@ai-sdk/sandbox-vercel";
import type * as ChatCatalog from "@chat-adapter/catalog";
import type { WhatsAppAdapter } from "@chat-adapter/whatsapp";
import type { Spec } from "@json-render/core";
import type {
  CommonPowerSyncDatabase,
  PowerSyncBackendConnector,
} from "@powersync/common";
import type * as Blob from "@vercel/blob";
import type * as Connect from "@vercel/connect";
import type * as ConnectChat from "@vercel/connect/chat";
import type * as ConnectEve from "@vercel/connect/eve";
import type * as ConnectMcp from "@vercel/connect/mcp";
import type { checkRateLimit } from "@vercel/firewall";
import type {
  addCacheTag,
  attachDatabasePool,
  getCache,
  invalidateByTag,
  metric,
} from "@vercel/functions";
import type * as Kms from "@vercel/kms";
import type { PassportIdentityPayload } from "@vercel/passport";
import type * as VercelSandbox from "@vercel/sandbox";
import type {
  ScheduleQueueMessage,
  Schedules as VercelSchedules,
} from "@vercel/schedules";
import type { Vercel } from "@vercel/sdk";
import type { checkBotId } from "botid/server";
import type { AuthFn } from "eve/channels/auth";
import type {
  ConnectionAuthDefinition,
  ProvidedArgumentValue,
} from "eve/connections";
import type { SessionAuthContext } from "eve/context";
import type {
  DefinedDynamicSchedules,
  ScheduleProvider as EveScheduleProviderContract,
  ScheduleProviderContext,
} from "eve/experimental/schedules";
import type { StreamEventHooks } from "eve/hooks";
import type { MemoryProvider } from "eve/memory";
import type { ScheduleRunHandler } from "eve/schedules";
import type { Approval, ApprovalConfiguration } from "eve/tools/approval";
import type {
  Adapter,
  FlagDeclaration,
  FlagOptionType,
  Identify,
  ProviderData,
} from "flags";
import type { Instrumentation } from "next";
import type { Publisher, Subscriber } from "resumable-stream/generic";
import type { registerLifecycleHooks } from "workflow/api";

import { describe, expectTypeOf, it } from "vitest";

import type { AnthropicMemoryTools } from "../src/ai-sdk/memory/index.ts";
import type { VercelDomainsSdk } from "../src/blocks/domains/index.ts";
import type {
  VercelScheduleQueueMessage,
  VercelSchedulesClient,
} from "../src/blocks/queue/index.ts";
import type { VercelKmsModule } from "../src/blocks/signing-keys/index.ts";
import type { WhatsappTemplateAdapter } from "../src/chat-sdk/index.ts";
import type {
  VercelCdnFunctions,
  vercelRuntimeCacheAdapter,
} from "../src/core/cache-vercel.ts";
import type { vercelRuntimeCache } from "../src/core/jwks-store.ts";
import type { CredentialSubject } from "../src/credentials/index.ts";
import type {
  EveApprovalConfiguration,
  ConnectEveFunction,
  EveConnectionAuthorization,
  EveDynamicSchedules,
  EveScheduleOptions,
  EveScheduleProviderContext,
  EveSessionAuth,
  EveToolApproval,
  approvalPolicy,
  persistSessions,
  queueDynamicSchedules,
  queueScheduleProvider,
  queueSchedules,
  supabaseJwtAuth,
  supabaseMemory,
  tenantArgument,
} from "../src/eve/index.ts";
import type {
  BetterSupabaseAdapterFactory,
  createIdentify,
  FlagsSdkAdapter,
  FlagsSdkEntities,
  FlagsSdkOption,
  FlagsSdkProviderData,
} from "../src/flags-sdk/index.ts";
import type { JsonRenderSpec } from "../src/json-render/index.ts";
import type { OnRequestError } from "../src/next/instrumentation/index.ts";
import type { VercelMetric } from "../src/otel/vercel/index.ts";
import type { AttachablePool } from "../src/postgres/pool.ts";
import type { SyncedDatabaseLike } from "../src/powersync/index.ts";
import type { VercelBlobModule } from "../src/storage/index.ts";
import type {
  postgresPublisher,
  postgresSubscriber,
} from "../src/streams/resumable/index.ts";
import type {
  ConnectEventVerifier,
  VercelConnectChatModule,
  VercelConnectModule,
} from "../src/vercel-connect/index.ts";
import type { PassportClaims } from "../src/vercel-passport/index.ts";
import type {
  VercelNetworkPolicy,
  VercelSandboxModule,
  VercelSandboxSessionModule,
} from "../src/vercel-sandbox/index.ts";
import type {
  CheckBotId,
  CheckRateLimit,
} from "../src/vercel-security/index.ts";
import type { WorkflowLifecycleOptions } from "../src/workflow-sdk/index.ts";

/**
 * The structural types better-supabase declares instead of importing an
 * optional peer, checked against the peer's real types at the installed
 * version. A major release that breaks one fails here.
 */
describe("structurally typed optional peers", () => {
  it("@vercel/connect has the functions the credential provider calls", () => {
    expectTypeOf<typeof Connect>().toExtend<VercelConnectModule>();
    expectTypeOf<typeof ConnectChat>().toExtend<VercelConnectChatModule>();
    expectTypeOf<CredentialSubject>().toExtend<Connect.ConnectTokenSubject>();
  });

  it("@vercel/connect/eve takes the options connectAuth passes", () => {
    expectTypeOf<typeof ConnectEve.connect>().toExtend<
      ConnectEveFunction<unknown>
    >();
  });

  it("@vercel/connect/mcp verifies the deliveries connectEventRoute reads", () => {
    expectTypeOf<
      typeof ConnectMcp.experimental_verifyMcpEvent
    >().toExtend<ConnectEventVerifier>();
  });

  it("@vercel/sandbox and its AI SDK adapter have what vercelSandboxes calls", () => {
    expectTypeOf<VercelSandbox.NetworkPolicy>().toExtend<VercelNetworkPolicy>();
    expectTypeOf<typeof VercelSandbox>().toExtend<VercelSandboxModule>();
    expectTypeOf<
      typeof SandboxSessions
    >().toExtend<VercelSandboxSessionModule>();
  });

  it("@vercel/schedules has what vercelScheduler calls and publishes the run vercelQueueRoute reads", () => {
    expectTypeOf<typeof VercelSchedules>().toExtend<VercelSchedulesClient>();
    expectTypeOf<ScheduleQueueMessage>().toExtend<VercelScheduleQueueMessage>();
  });

  it("botid and @vercel/firewall have the checks the vercel-security guards call", () => {
    expectTypeOf<typeof checkBotId>().toExtend<CheckBotId>();
    expectTypeOf<typeof checkRateLimit>().toExtend<CheckRateLimit>();
  });

  it("@vercel/passport's payload and PassportClaims are assignable to each other", () => {
    expectTypeOf<PassportIdentityPayload>().toExtend<PassportClaims>();
    expectTypeOf<PassportClaims>().toExtend<PassportIdentityPayload>();
  });

  it("@vercel/functions takes the pool and gives the cache the server options use", () => {
    expectTypeOf<typeof attachDatabasePool>().toExtend<
      (pool: AttachablePool) => void
    >();
    expectTypeOf<typeof getCache>().toExtend<
      Parameters<typeof vercelRuntimeCache>[0]
    >();
  });

  it("@vercel/functions gives the Runtime Cache tags and the CDN purge the cache adapters use", () => {
    expectTypeOf<typeof getCache>().toExtend<
      Parameters<typeof vercelRuntimeCacheAdapter>[0]
    >();
    expectTypeOf<{
      addCacheTag: typeof addCacheTag;
      invalidateByTag: typeof invalidateByTag;
    }>().toExtend<VercelCdnFunctions>();
  });

  it("@vercel/functions' metric is the function vercelMetrics takes", () => {
    expectTypeOf<typeof metric>().toExtend<VercelMetric>();
    expectTypeOf<VercelMetric>().toExtend<typeof metric>();
  });

  it("Next.js's onRequestError and the bridge take each other's arguments", () => {
    expectTypeOf<OnRequestError>().toExtend<Instrumentation.onRequestError>();
    expectTypeOf<Instrumentation.onRequestError>().toExtend<
      (...args: Parameters<OnRequestError>) => void | Promise<void>
    >();
  });

  it("the Workflow SDK takes the lifecycle hooks registerWorkflowLifecycle installs", () => {
    expectTypeOf<typeof registerLifecycleHooks>().toExtend<
      NonNullable<WorkflowLifecycleOptions["register"]>
    >();
  });

  it("@vercel/sdk, @vercel/kms and @vercel/blob have what the domain, key and file providers call", () => {
    expectTypeOf<Vercel>().toExtend<VercelDomainsSdk>();
    expectTypeOf<typeof Kms>().toExtend<VercelKmsModule>();
    expectTypeOf<typeof Blob>().toExtend<VercelBlobModule>();
  });

  it("@chat-adapter/whatsapp's adapter sends the template shape sendWithinWindowOrTemplate passes", () => {
    expectTypeOf<WhatsAppAdapter>().toExtend<WhatsappTemplateAdapter>();
  });

  it("@chat-adapter/catalog has the lookups the chat-sdk helpers will read", () => {
    expectTypeOf<typeof ChatCatalog.listAdapters>().toBeFunction();
    expectTypeOf<typeof ChatCatalog.getAdapter>().toBeFunction();
    expectTypeOf<typeof ChatCatalog.getSecretEnvVars>().toBeFunction();
  });

  it("@ai-sdk/anthropic has the pinned memory tool", () => {
    expectTypeOf<typeof anthropic.tools>().toExtend<AnthropicMemoryTools>();
  });

  it("the Flags SDK takes the adapter, called or by reference", () => {
    type Declared = NonNullable<
      FlagDeclaration<boolean, FlagsSdkEntities>["adapter"]
    >;

    expectTypeOf<FlagsSdkAdapter<boolean>>().toExtend<
      Adapter<boolean, FlagsSdkEntities>
    >();
    expectTypeOf<BetterSupabaseAdapterFactory>().toExtend<Declared>();
    expectTypeOf<ReturnType<typeof createIdentify>>().toExtend<
      Identify<FlagsSdkEntities>
    >();
    expectTypeOf<FlagsSdkProviderData>().toExtend<ProviderData>();
    expectTypeOf<FlagsSdkOption[]>().toExtend<FlagOptionType[]>();
  });

  it("eve takes the session auth, memory, connection, tool, approval, hook and schedule shapes", () => {
    expectTypeOf<EveSessionAuth>().toExtend<SessionAuthContext>();
    expectTypeOf<SessionAuthContext>().toExtend<EveSessionAuth>();
    expectTypeOf<
      ReturnType<typeof supabaseMemory>
    >().toExtend<MemoryProvider>();
    expectTypeOf<EveConnectionAuthorization>().toExtend<ConnectionAuthDefinition>();
    expectTypeOf<EveApprovalConfiguration>().toExtend<ApprovalConfiguration>();
    expectTypeOf<ReturnType<typeof approvalPolicy>>().toExtend<Approval>();
    expectTypeOf<EveToolApproval>().toExtend<Approval>();
    expectTypeOf<
      ReturnType<typeof persistSessions>
    >().toExtend<StreamEventHooks>();
    expectTypeOf<
      ReturnType<typeof queueSchedules>
    >().toExtend<ScheduleRunHandler>();
    expectTypeOf<
      ReturnType<typeof tenantArgument>[string]
    >().toExtend<ProvidedArgumentValue>();
    expectTypeOf<
      EveScheduleOptions["appAuth"]
    >().toExtend<SessionAuthContext>();
    expectTypeOf<ReturnType<typeof supabaseJwtAuth>>().toExtend<AuthFn>();
  });

  it("eve takes the queue-backed dynamic schedules provider and its tick", () => {
    expectTypeOf<
      ReturnType<typeof queueScheduleProvider>
    >().toExtend<EveScheduleProviderContract>();
    expectTypeOf<ScheduleProviderContext>().toExtend<EveScheduleProviderContext>();
    expectTypeOf<
      DefinedDynamicSchedules<{ readonly task: string }>
    >().toExtend<EveDynamicSchedules>();
    expectTypeOf<
      ReturnType<typeof queueDynamicSchedules>
    >().toExtend<ScheduleRunHandler>();
  });

  it("a PowerSync database has what syncWithAuth drives", () => {
    expectTypeOf<CommonPowerSyncDatabase>().toExtend<
      SyncedDatabaseLike<PowerSyncBackendConnector>
    >();
  });

  it("a json-render spec and the Postgres publisher and subscriber fit the packages' types", () => {
    expectTypeOf<Spec>().toExtend<JsonRenderSpec>();
    expectTypeOf<ReturnType<typeof postgresPublisher>>().toExtend<Publisher>();
    expectTypeOf<
      ReturnType<typeof postgresSubscriber>
    >().toExtend<Subscriber>();
  });
});
