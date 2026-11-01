import type { SupabaseClient } from "@supabase/supabase-js";
import type { QueryClient } from "@tanstack/react-query";
import type { createClient } from "redis";

import * as v from "valibot";
import { describe, expectTypeOf, it } from "vitest";

import type { AuthResolver } from "../../src/auth/resolve.ts";
import type {
  NoteTaker,
  Transcriber,
} from "../../src/blocks/activities/index.ts";
import type { AiTaskRunner } from "../../src/blocks/ai-schedules/index.ts";
import type { FieldPack } from "../../src/blocks/custom-fields/index.ts";
import type { Embedder } from "../../src/blocks/knowledge/index.ts";
import type {
  DeliveryTransport,
  NotificationChannel,
} from "../../src/blocks/notifications/index.ts";
import type {
  InvitationSent,
  InviteRequest,
} from "../../src/blocks/organizations/index.ts";
import type { Profiles } from "../../src/blocks/profiles/index.ts";
import type { QueueProvider } from "../../src/blocks/queue/index.ts";
import type { ShippingProvider } from "../../src/blocks/shipments/index.ts";
import type {
  IncomingDestination,
  WebhookSecretStore,
  WebhookSigner,
  WebhookTransport,
} from "../../src/blocks/webhooks/index.ts";
import type {
  BuilderStarter,
  GraphCompiler,
} from "../../src/blocks/workflow-editor/index.ts";
import type { PaymentProvider, TaxProvider } from "../../src/commerce/index.ts";
import type {
  AuthorizationProvider,
  AuthorizationVersions,
  BetterSupabaseConfig,
  Generator,
} from "../../src/config/index.ts";
import type {
  AuthorizationOutcome,
  AuthorizationRequest,
  Authorizer,
  AuthorizerRuntime,
  AuthzVersionCache,
  PermissionRef,
} from "../../src/core/authorizer.ts";
import type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../src/core/block-hooks.ts";
import type { BlockTransport } from "../../src/core/block-transport.ts";
import type { CacheAdapter } from "../../src/core/cache.ts";
import type { Compiler } from "../../src/core/compiler.ts";
import type { Executor } from "../../src/core/executor.ts";
import type { Logger } from "../../src/core/logger.ts";
import type {
  AnyPlugin,
  MutationEvent,
  MutationIntent,
  RequestContext,
} from "../../src/core/plugin.ts";
import type { AsyncResult, Result } from "../../src/core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../src/credentials/index.ts";
import type {
  EInvoiceChannel,
  EInvoiceFormat,
} from "../../src/e-invoicing/index.ts";
import type { EveDocumentBackend } from "../../src/eve/index.ts";
import type { EventSink } from "../../src/events/index.ts";
import type { Operation } from "../../src/ir/types.ts";
import type {
  OpenApiDocuments,
  OpenApiVersion,
} from "../../src/openapi/types.ts";
import type {
  AuthorizationHooks,
  ServerContext,
  SupportSessionStore,
} from "../../src/server/index.ts";
import type {
  AnyDocumentFormat,
  DocumentFormat,
  DocumentOf,
  RenderedOf,
  SpecDiagnostic,
  VersionOf,
} from "../../src/spec/format.ts";
import type { ApiModel } from "../../src/spec/model.ts";
import type { StreamStore } from "../../src/streams/index.ts";
import type {
  RedisStreamClient,
  RedisStreamSubscriber,
} from "../../src/streams/redis/index.ts";
import type { TestDocumentFormatOptions } from "../../src/testing/document-format.ts";

import { membershipsExtension } from "../../src/blocks/memberships/index.ts";
import { createOrganizations } from "../../src/blocks/organizations/index.ts";
import { permissionsAuthorizer } from "../../src/blocks/permissions/index.ts";
import { createProfiles } from "../../src/blocks/profiles/index.ts";
import {
  pgmqPublicBackend,
  sqlQueueProvider,
} from "../../src/blocks/queue/index.ts";
import { flatRateCarrier } from "../../src/blocks/shipments/index.ts";
import { trashExtension } from "../../src/blocks/trash/index.ts";
import { updatedAtExtension } from "../../src/blocks/updated-at/index.ts";
import {
  fetchTransport,
  hmacSigner,
  inboxDestination,
  jobsDestination,
  sqlSecretStore,
  standardWebhooks,
} from "../../src/blocks/webhooks/index.ts";
import {
  fixedRates,
  stripePayments,
  stripeTax,
} from "../../src/commerce/index.ts";
import { jsonSchema } from "../../src/config/index.ts";
import { bindAuthorizer } from "../../src/core/authorizer.ts";
import {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../src/core/block-hooks.ts";
import { memoryCache } from "../../src/core/cache.ts";
import { postgrestCompiler } from "../../src/core/compiler.ts";
import { defineRepository } from "../../src/core/define-repository.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { consoleLogger, silentLogger } from "../../src/core/logger.ts";
import { postgrestExecutor } from "../../src/core/postgrest-executor.ts";
import { httpSink } from "../../src/events/index.ts";
import { valibot } from "../../src/generators/valibot.ts";
import { zod } from "../../src/generators/zod.ts";
import { nextCache } from "../../src/next/index.ts";
import { openapiFormat } from "../../src/openapi/format.ts";
import { postgresExecutor, sqlCompiler } from "../../src/postgres/index.ts";
import { queryCache } from "../../src/query/index.ts";
import { sqlSupportStore } from "../../src/server/index.ts";
import { defineDocumentFormat } from "../../src/spec/format.ts";
import { staticAuthorizer } from "../../src/testing/authorizer.ts";
import { testDocumentFormat } from "../../src/testing/document-format.ts";
import { schema } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
declare const queryClient: QueryClient;
declare const blockTransport: BlockTransport;

describe("extension interfaces", () => {
  it("are implemented by the first-party extensions", () => {
    expectTypeOf(postgrestExecutor(client)).toExtend<Executor>();
    expectTypeOf(postgresExecutor).returns.toExtend<Executor>();
    expectTypeOf(postgrestCompiler).toExtend<Compiler<unknown>>();
    expectTypeOf(sqlCompiler).toExtend<Compiler<unknown>>();
    expectTypeOf(memoryCache()).toExtend<CacheAdapter>();
    expectTypeOf(nextCache()).toExtend<CacheAdapter>();
    expectTypeOf(queryCache(queryClient)).toExtend<CacheAdapter>();
    expectTypeOf(httpSink).returns.toExtend<EventSink>();
    expectTypeOf(sqlQueueProvider).returns.toExtend<QueueProvider>();
    expectTypeOf(pgmqPublicBackend).returns.toExtend<QueueProvider>();
    expectTypeOf<QueueProvider["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf(sqlSupportStore).returns.toExtend<SupportSessionStore>();
    expectTypeOf<SupportSessionStore["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<NotificationChannel["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<DeliveryTransport["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<AuthorizationHooks["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf(stripePayments).returns.toExtend<PaymentProvider>();
    expectTypeOf<PaymentProvider["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf(fixedRates).returns.toExtend<TaxProvider>();
    expectTypeOf(stripeTax).returns.toExtend<TaxProvider>();
    expectTypeOf<TaxProvider["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf(flatRateCarrier).returns.toExtend<ShippingProvider>();
    expectTypeOf<ShippingProvider["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<EInvoiceChannel["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<EInvoiceFormat["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<FieldPack["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf(standardWebhooks).returns.toExtend<WebhookSigner>();
    expectTypeOf(hmacSigner).returns.toExtend<WebhookSigner>();
    expectTypeOf(fetchTransport).returns.toExtend<WebhookTransport>();
    expectTypeOf(sqlSecretStore).returns.toExtend<WebhookSecretStore>();
    expectTypeOf(inboxDestination).returns.toExtend<IncomingDestination>();
    expectTypeOf(jobsDestination).returns.toExtend<IncomingDestination>();
    expectTypeOf<IncomingDestination["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<WebhookSigner["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<WebhookTransport["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<WebhookSecretStore["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf(consoleLogger).toExtend<Logger>();
    expectTypeOf(silentLogger).toExtend<Logger>();
    expectTypeOf(zod()).toExtend<Generator>();
    expectTypeOf(valibot()).toExtend<Generator>();
    expectTypeOf(jsonSchema()).toExtend<Generator>();
    expectTypeOf(updatedAtExtension()).toExtend<AnyPlugin>();
    expectTypeOf<AuthResolver["resolve"]>()
      .parameter(0)
      .toEqualTypeOf<Request>();
  });

  it("keeps Executor.batch optional, so existing executors still conform", () => {
    const minimal: Executor = {
      name: "minimal",
      execute: () => Promise.reject(new Error("unused")),
    };

    expectTypeOf(minimal).toExtend<Executor>();
    expectTypeOf<NonNullable<Executor["batch"]>>()
      .parameter(0)
      .toEqualTypeOf<readonly Operation[]>();
    expectTypeOf<Executor["functionSources"]>().toEqualTypeOf<
      boolean | undefined
    >();
  });

  it("keeps the Plugin context hook optional and context-shaped", () => {
    expectTypeOf<{ name: "bare"; apiVersion: 1 }>().toExtend<AnyPlugin>();
    expectTypeOf<NonNullable<AnyPlugin["context"]>>()
      .parameter(0)
      .toEqualTypeOf<RequestContext>();
    expectTypeOf<
      NonNullable<AnyPlugin["context"]>
    >().returns.toEqualTypeOf<RequestContext>();
  });
});

describe("AuthorizationProvider", () => {
  it("is versioned plain data on the config", () => {
    expectTypeOf<AuthorizationProvider["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<
      NonNullable<BetterSupabaseConfig["auth"]>["authorization"]
    >().toEqualTypeOf<AuthorizationProvider | undefined>();

    const minimal = {
      apiVersion: 1,
      name: "minimal",
      scopes: [{ name: "tenant" }],
      tenantScope: "tenant",
      functions: {
        idsWith: "authz.ids_with({permission}, '{scope}')",
        isPlatform: "authz.is_platform({permission})",
      },
    } as const satisfies AuthorizationProvider;

    expectTypeOf(minimal).toExtend<AuthorizationProvider>();
    const accepts = (provider: AuthorizationProvider) => provider;
    // @ts-expect-error a provider needs the two caller templates
    accepts({ ...minimal, functions: {} });
  });

  it("keeps the authorization versions without a new apiVersion", () => {
    expectTypeOf<AuthorizationProvider["versions"]>().toEqualTypeOf<
      AuthorizationVersions | undefined
    >();
    expectTypeOf<AuthorizationVersions>().toEqualTypeOf<{
      readonly function: string;
    }>();
  });
});

describe("Authorizer", () => {
  it("is versioned, with an optional batch form", () => {
    expectTypeOf<Authorizer["apiVersion"]>().toEqualTypeOf<1>();

    const minimal: Authorizer<"read"> = {
      apiVersion: 1,
      name: "minimal",
      key: (ref) => ref,
      evaluate: () => ({ outcome: "denied" }),
    };

    expectTypeOf(minimal).toExtend<Authorizer<"read">>();
    expectTypeOf<Authorizer<"read">["evaluations"]>().toEqualTypeOf<
      | ((
          requests: readonly AuthorizationRequest<"read">[],
          runtime?: AuthorizerRuntime,
        ) => Promise<readonly AuthorizationOutcome[]>)
      | undefined
    >();
  });

  it("ships permissionsAuthorizer over the generated key union", () => {
    const permissions = {
      invoices: { read: "invoices.read", write: "invoices.write" },
    } as const;

    const authorizer = permissionsAuthorizer<
      "invoices.read" | "invoices.write"
    >({ permissions });

    expectTypeOf(authorizer).toEqualTypeOf<
      Authorizer<"invoices.read" | "invoices.write">
    >();
    expectTypeOf(authorizer.apiVersion).toEqualTypeOf<1>();
  });

  it("takes an optional runtime, so v1 authorizers without one still fit", () => {
    const versions: AuthzVersionCache = { evict: () => undefined };
    const seen: (AuthorizerRuntime | undefined)[] = [];

    const withRuntime: Authorizer<"read"> = {
      apiVersion: 1,
      name: "versioned",
      key: (ref) => ref,
      evaluate: (_request, runtime) => {
        seen.push(runtime);

        return { outcome: "granted" };
      },
    };

    expectTypeOf(bindAuthorizer(withRuntime, { versions })).toEqualTypeOf<
      Authorizer<"read">
    >();
    expectTypeOf(seen).toEqualTypeOf<(AuthorizerRuntime | undefined)[]>();
  });

  it("carries its permission type to adapters", () => {
    const authorizer = staticAuthorizer<"export" | "invite">({
      roles: { authenticated: ["export"] },
    });

    expectTypeOf(authorizer).toExtend<Authorizer<"export" | "invite">>();
    expectTypeOf<PermissionRef<typeof authorizer>>().toEqualTypeOf<
      "export" | "invite"
    >();
    expectTypeOf<PermissionRef<undefined>>().toEqualTypeOf<string>();
    // @ts-expect-error a role lists only known permissions
    staticAuthorizer<"export">({ roles: { authenticated: ["delete"] } });
  });
});

describe("DocumentFormat", () => {
  it("is versioned, and openapiFormat implements it", () => {
    expectTypeOf<DocumentFormat["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf(openapiFormat).toExtend<AnyDocumentFormat>();
    expectTypeOf<
      VersionOf<typeof openapiFormat>
    >().toEqualTypeOf<OpenApiVersion>();
    expectTypeOf<DocumentFormat["lint"]>().toEqualTypeOf<
      ((doc: unknown, version: string) => readonly SpecDiagnostic[]) | undefined
    >();
  });

  it("types each version's document for transform hooks", () => {
    expectTypeOf<
      Extract<RenderedOf<typeof openapiFormat>, { version: "3.0" }>["document"]
    >().toEqualTypeOf<OpenApiDocuments["3.0"]>();
    expectTypeOf<
      RenderedOf<typeof openapiFormat>["format"]
    >().toEqualTypeOf<"openapi">();
  });

  it("infers a third-party format and its versions", () => {
    const text = defineDocumentFormat({
      id: "operation-list",
      versions: {
        "1": { pin: "1.0.0", status: "stable" },
        "2-draft": { pin: "abc1234", status: "preview" },
      },
      defaultVersion: "1",
      lower: (model: ApiModel) => model.operations.map((op) => op.id).join(","),
      fileName: () => "operations.txt",
    });

    expectTypeOf<VersionOf<typeof text>>().toEqualTypeOf<"1" | "2-draft">();
    expectTypeOf<DocumentOf<typeof text>>().toEqualTypeOf<string>();
    expectTypeOf(testDocumentFormat<typeof text>)
      .parameter(1)
      .toEqualTypeOf<TestDocumentFormatOptions<"1" | "2-draft"> | undefined>();
    defineDocumentFormat({
      id: "bad",
      versions: { "1": { pin: "1.0.0", status: "stable" } },
      // @ts-expect-error the default version must be one of the versions
      defaultVersion: "2",
      lower: () => ({}),
      fileName: () => "bad.json",
    });
  });
});

describe("CredentialProvider", () => {
  it("is versioned and optional on the server context", () => {
    expectTypeOf<CredentialProvider["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<
      ServerContext<never, never, never>["credentials"]
    >().toEqualTypeOf<CredentialProvider | undefined>();
    expectTypeOf<{
      provider: "vault";
      secret: "x";
    }>().toExtend<CredentialRef>();
    const accepts = (provider: CredentialProvider) => provider;
    // @ts-expect-error a provider resolves tokens and revokes them
    accepts({ apiVersion: 1, name: "partial", capabilities: () => ({}) });
  });
});

describe("block injectables", () => {
  it("carry an optional apiVersion 1, and plain functions still fit", () => {
    expectTypeOf<Embedder["apiVersion"]>().toEqualTypeOf<1 | undefined>();
    expectTypeOf<AiTaskRunner["apiVersion"]>().toEqualTypeOf<1 | undefined>();
    expectTypeOf<GraphCompiler["apiVersion"]>().toEqualTypeOf<1 | undefined>();
    expectTypeOf<BuilderStarter["apiVersion"]>().toEqualTypeOf<1 | undefined>();
    expectTypeOf<EveDocumentBackend["apiVersion"]>().toEqualTypeOf<
      1 | undefined
    >();
    expectTypeOf<Transcriber["apiVersion"]>().toEqualTypeOf<1 | undefined>();
    expectTypeOf<NoteTaker["apiVersion"]>().toEqualTypeOf<1 | undefined>();
    expectTypeOf(async () => undefined).toExtend<AiTaskRunner>();
    expectTypeOf(async () => "run_1").toExtend<BuilderStarter>();
    expectTypeOf(() => ({})).toExtend<GraphCompiler>();
    const accepts = (embedder: Embedder) => embedder;
    // @ts-expect-error only API 1 exists
    accepts({ apiVersion: 2, model: "m", embed: async () => [] });
  });
});

describe("StreamStore", () => {
  it("is versioned, and node-redis clients fit the Redis store", () => {
    expectTypeOf<StreamStore["apiVersion"]>().toEqualTypeOf<1>();

    type NodeRedis = ReturnType<typeof createClient>;

    expectTypeOf<NodeRedis>().toExtend<RedisStreamClient>();
    expectTypeOf<NodeRedis>().toExtend<RedisStreamSubscriber>();
  });
});

describe("defineRepository", () => {
  const betterSupabase = defineSupabase(schema)
    .use(trashExtension())
    .use(membershipsExtension());

  const tags = defineRepository(betterSupabase, "tags", (base) => ({
    named: (name: string) =>
      base
        .list({ where: { name }, select: ["id", "name"], limit: 1 })
        .map((rows) => rows[0] ?? null),
  }));

  const db = betterSupabase.use(tags).connect(client);

  it("types methods on the target table only", () => {
    expectTypeOf(db.tags.named).parameters.toEqualTypeOf<[name: string]>();
    expectTypeOf(db.tags.named("x")).toEqualTypeOf<
      AsyncResult<{ id: string; name: string } | null>
    >();
    expectTypeOf(db.customers).not.toHaveProperty("named");
  });

  it("keeps plugin extensions on the base repository", () => {
    defineRepository(betterSupabase, "customers", (base) => {
      expectTypeOf(base).toHaveProperty("restore");

      return {};
    });
  });

  it("accepts only known tables", () => {
    // @ts-expect-error unknown table
    defineRepository(betterSupabase, "nope", () => ({}));
  });
});

describe("mutation events", () => {
  it("carry the intent, the known keys and the resolved tenant", () => {
    expectTypeOf<MutationEvent["intent"]>().toEqualTypeOf<
      MutationIntent | undefined
    >();
    expectTypeOf<MutationIntent>().toEqualTypeOf<
      "insert" | "upsert" | "update" | "delete" | "softDelete"
    >();
    expectTypeOf<MutationEvent["tenant"]>().toEqualTypeOf<string | undefined>();
    expectTypeOf<MutationEvent["keys"]>().toEqualTypeOf<
      readonly Readonly<Record<string, unknown>>[] | undefined
    >();
  });
});

describe("block extension", () => {
  const Fields = v.object({
    plan: v.picklist(["free", "pro"]),
    seats: v.number(),
  });

  it("types the extra fields on reads and writes", () => {
    const organizations = createOrganizations({
      transport: blockTransport,
      fields: Fields,
    });

    expectTypeOf(organizations.mine()).resolves.toExtend<
      | { ok: true; data: readonly { plan: "free" | "pro"; seats: number }[] }
      | { ok: false }
    >();
    expectTypeOf<Parameters<(typeof organizations)["update"]>[1]>()
      .toHaveProperty("plan")
      .toEqualTypeOf<"free" | "pro" | undefined>();

    const profiles = createProfiles({
      transport: blockTransport,
      fields: Fields,
    });

    expectTypeOf(profiles).toEqualTypeOf<
      Profiles<{ plan: "free" | "pro"; seats: number }>
    >();
    expectTypeOf(
      createProfiles({ transport: blockTransport }),
    ).toEqualTypeOf<Profiles>();
  });

  it("types hooks by method", () => {
    createOrganizations({
      transport: blockTransport,
      hooks: {
        invite: {
          before: ([request]) => {
            expectTypeOf(request).toEqualTypeOf<InviteRequest>();
          },
          after: (result) => {
            expectTypeOf(result).toEqualTypeOf<Result<InvitationSent>>();
          },
        },
        // @ts-expect-error not a method
        nope: {},
      },
    });
  });

  it("adds methods with extendBlock and keeps the base", () => {
    const extended = extendBlock(
      createProfiles({ transport: blockTransport }),
      (base, { call }) => ({
        touch: () => call("touch_profile", {}, () => true as const),
        reread: () => base.mine(),
      }),
    );

    expectTypeOf(extended.touch()).toEqualTypeOf<AsyncResult<true>>();
    expectTypeOf(extended).toHaveProperty("updateMine");
  });

  it("versions transport middleware", () => {
    expectTypeOf<BlockTransportMiddleware["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf(wrapTransport).returns.toExtend<BlockTransport>();
    expectTypeOf(withBlockHooks<Profiles>)
      .parameter(1)
      .toEqualTypeOf<BlockHooks<Profiles> | undefined>();
  });
});
