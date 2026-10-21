import type { BlockCall } from "../../core/block-helpers.ts";
import type { BlockProblemOptions } from "../../core/problem.ts";
import type { AsyncResult, Result } from "../../core/result.ts";
import type {
  MarketplaceInstallation,
  MarketplaceResource,
  VercelMarketplace,
} from "./vercel-marketplace.ts";

import { type DbError, dbError, dbErrorOf } from "../../core/errors.ts";
import { methodNotAllowed, problemResponse } from "../../core/problem.ts";
import { errorText, isRecord, optionalText } from "../shared.ts";

/** The Vercel environments a resource's secrets reach. */
export type VercelEnvironment = "production" | "preview" | "development";

export const VERCEL_ENVIRONMENTS: readonly VercelEnvironment[] = [
  "production",
  "preview",
  "development",
];

/** A secret Vercel turns into an environment variable of the projects that use the resource. */
export interface MarketplaceSecret {
  readonly name: string;
  readonly value: string;
  readonly prefix?: string;
  /** A different value per Vercel environment, such as a tenant environment each. */
  readonly environmentOverrides?: Readonly<
    Partial<Record<VercelEnvironment, string>>
  >;
  /**
   * The app's handle for the secret, such as an API key id. The block keeps it
   * (never the value) so a rotation can revoke the previous secret; Vercel
   * never sees it.
   */
  readonly ref?: string;
}

/** A billing plan, as `GET /v1/products/{id}/plans` returns it. */
export interface MarketplacePlan {
  readonly id: string;
  readonly name: string;
  readonly type: "subscription" | "prepayment";
  readonly scope?: "installation" | "resource";
  readonly description?: string;
  readonly paymentMethodRequired?: boolean;
  readonly details?: readonly {
    readonly label: string;
    readonly value?: string;
  }[];
  /** The priced items; a free plan has none. */
  readonly billing?: { readonly items: readonly unknown[] };
  readonly [field: string]: unknown;
}

/** The resource Vercel asks the app to provision. */
export interface MarketplaceResourceRequest {
  readonly id: string;
  readonly productId: string | undefined;
  readonly name: string;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly billingPlanId: string | undefined;
}

export interface MarketplaceProvisionInput {
  readonly installation: MarketplaceInstallation;
  readonly resource: MarketplaceResourceRequest;
  readonly plan: MarketplacePlan | undefined;
  /** Every Vercel environment, for an app that keeps one tenant environment per Vercel environment. */
  readonly environments: readonly VercelEnvironment[];
}

export interface MarketplaceProvisionResult {
  /** The app's tenant for the resource. */
  readonly tenant?: string;
  /** Whether the hook created the tenant, so deleting the resource may delete it. */
  readonly tenantCreated?: boolean;
  readonly secrets: readonly MarketplaceSecret[];
}

export interface MarketplaceResourceHooks {
  /** Creates what the resource stands for and returns its secrets. */
  provision(
    input: MarketplaceProvisionInput,
  ): Promise<MarketplaceProvisionResult>;
  /** Applies a rename, new metadata or a plan change. */
  update?(input: {
    readonly installation: MarketplaceInstallation;
    readonly resource: MarketplaceResource;
    readonly changes: {
      readonly name?: string;
      readonly metadata?: Readonly<Record<string, unknown>>;
      readonly billingPlanId?: string;
    };
  }): Promise<void>;
  /** Tears the resource down, before its tenant is removed. */
  deprovision?(input: {
    readonly installation: MarketplaceInstallation;
    readonly resource: MarketplaceResource;
  }): Promise<void>;
  /** Issues new secrets. `revoke` runs only after this resolves. */
  rotate?(input: {
    readonly installation: MarketplaceInstallation;
    readonly resource: MarketplaceResource;
    readonly reason: string | undefined;
  }): Promise<{ readonly secrets: readonly MarketplaceSecret[] }>;
  /** Revokes the secrets a rotation replaced, by the `ref` they were handed out with. */
  revoke?(input: {
    readonly installation: MarketplaceInstallation;
    readonly resource: MarketplaceResource;
    readonly previous: readonly string[];
    /** Hours Vercel asked to keep the old secrets valid. */
    readonly delayHours: number | undefined;
  }): Promise<void>;
}

export interface MarketplaceTenantRemoval {
  readonly installation: MarketplaceInstallation;
  readonly tenant: string;
  /** Whether the installation or the provision hook created the tenant. */
  readonly created: boolean;
}

/** The part of the organizations block the default `removeTenant` uses. */
export interface MarketplaceOrganizations {
  delete(organizationId: string): AsyncResult<boolean>;
  members(organizationId: string): AsyncResult<readonly unknown[]>;
}

export interface PartnerApiOptions extends BlockProblemOptions {
  readonly resources: MarketplaceResourceHooks;
  /** Runs after `PUT /v1/installations/{id}` stored the installation; may link a tenant. */
  readonly install?: (input: {
    readonly installation: MarketplaceInstallation;
    readonly account: Readonly<Record<string, unknown>>;
    readonly scopes: readonly string[];
  }) => Promise<
    | { readonly tenant?: string; readonly tenantCreated?: boolean }
    | undefined
    | void
  >;
  /**
   * Removes a tenant when its resource or installation goes away. Default:
   * deletes it through `organizations` when the installation created it and
   * it has no members, and does nothing without `organizations`.
   */
  readonly removeTenant?: (input: MarketplaceTenantRemoval) => Promise<void>;
  readonly organizations?: MarketplaceOrganizations;
  /** The plans the integration sells, or a function of the product and installation. */
  readonly plans?:
    | readonly MarketplacePlan[]
    | ((input: {
        readonly productId: string | undefined;
        readonly installation: MarketplaceInstallation | undefined;
      }) => Promise<readonly MarketplacePlan[]>);
  /** New resource ids for `POST .../resources`. Default: `crypto.randomUUID()`. */
  readonly resourceId?: () => string;
  /** Include the messages of internal errors in responses. Default: false. */
  readonly expose?: boolean;
}

/** What the handler needs from the block. */
export interface PartnerApiDeps {
  readonly marketplace: VercelMarketplace;
  readonly call: BlockCall;
  readonly verifyToken: (
    token: string,
  ) => Promise<Result<Readonly<Record<string, unknown>>>>;
}

const SECRET_NAME = /^[A-Za-z_][A-Za-z0-9_]*$/u;

class Answer extends Error {
  readonly error: DbError;

  constructor(error: DbError) {
    super(error.message);
    this.error = error;
  }
}

const fail = (error: DbError): never => {
  throw new Answer(error);
};

async function data<T>(result: AsyncResult<T>): Promise<T> {
  const settled = await result;

  return settled.ok ? settled.data : fail(settled.error);
}

function secretsOf(value: unknown, hook: string): readonly MarketplaceSecret[] {
  const malformed = (): never =>
    fail(
      dbError(
        "unexpected",
        `${hook} must return secrets: [{ name, value, environmentOverrides? }]`,
        { hint: "MARKETPLACE_SECRETS_SHAPE" },
      ),
    );

  if (!Array.isArray(value)) {
    return malformed();
  }

  return value.map((secret: unknown): MarketplaceSecret => {
    if (!isRecord(secret)) {
      return malformed();
    }

    const { name, value: secretValue, prefix, ref } = secret;

    if (
      typeof name !== "string" ||
      !SECRET_NAME.test(name) ||
      typeof secretValue !== "string" ||
      (prefix !== undefined && typeof prefix !== "string") ||
      (ref !== undefined && typeof ref !== "string")
    ) {
      return malformed();
    }

    const overrides = secret["environmentOverrides"];
    const environmentOverrides: Partial<Record<VercelEnvironment, string>> = {};

    if (overrides !== undefined) {
      if (!isRecord(overrides)) {
        return malformed();
      }

      for (const [environment, override] of Object.entries(overrides)) {
        const known = VERCEL_ENVIRONMENTS.find(
          (candidate) => candidate === environment,
        );

        if (known === undefined || typeof override !== "string") {
          return malformed();
        }

        environmentOverrides[known] = override;
      }
    }

    return {
      name,
      value: secretValue,
      ...(prefix === undefined ? {} : { prefix }),
      ...(overrides === undefined ? {} : { environmentOverrides }),
      ...(ref === undefined ? {} : { ref }),
    };
  });
}

/** The secrets as Vercel takes them, without the app's refs. */
const publicSecrets = (
  secrets: readonly MarketplaceSecret[],
): readonly Omit<MarketplaceSecret, "ref">[] =>
  secrets.map(({ ref: _ref, ...secret }) => secret);

const refsOf = (secrets: readonly MarketplaceSecret[]): readonly string[] =>
  secrets.flatMap((secret) => (secret.ref === undefined ? [] : [secret.ref]));

const vercelStatus = (status: MarketplaceResource["status"]): string =>
  status === "deleted" ? "uninstalled" : status;

function resourceBody(
  resource: MarketplaceResource,
  secrets?: readonly MarketplaceSecret[],
): Record<string, unknown> {
  return {
    id: resource.externalId,
    productId: optionalText(resource.metadata["productId"]),
    name: resource.name,
    metadata: resource.metadata["vercel"] ?? {},
    status: vercelStatus(resource.status),
    ...(resource.planId === undefined
      ? {}
      : { billingPlan: { id: resource.planId } }),
    ...(secrets === undefined ? {} : { secrets: publicSecrets(secrets) }),
  };
}

async function bodyOf(request: Request): Promise<Record<string, unknown>> {
  const text = await request.text();

  if (text === "") {
    return {};
  }

  try {
    const parsed: unknown = JSON.parse(text);

    if (isRecord(parsed)) {
      return parsed;
    }
  } catch {
    // Reported below.
  }

  return fail(
    dbError("invalid_input", "The request body is not a JSON object", {
      hint: "MARKETPLACE_BODY",
    }),
  );
}

const recordField = (
  body: Readonly<Record<string, unknown>>,
  name: string,
): Readonly<Record<string, unknown>> => {
  const value = body[name];

  return isRecord(value) ? value : {};
};

/**
 * The Vercel Marketplace Partner API as one `Request` to `Response` handler:
 * installations, resources, secret rotation and plans, each request checked
 * against Vercel's OIDC token. Mount it under any prefix; it routes from the
 * `/v1/` segment on.
 */
export function createPartnerApi(
  deps: PartnerApiDeps,
  options: PartnerApiOptions,
): (request: Request) => Promise<Response> {
  const { marketplace, call } = deps;
  const newId = options.resourceId ?? ((): string => crypto.randomUUID());

  const removeTenant =
    options.removeTenant ??
    (async ({ tenant, created }: MarketplaceTenantRemoval): Promise<void> => {
      const organizations = options.organizations;

      if (!created || organizations === undefined) {
        return;
      }

      const members = await data(organizations.members(tenant));

      if (members.length === 0) {
        await data(organizations.delete(tenant));
      }
    });

  const plansFor = async (
    productId: string | undefined,
    installation: MarketplaceInstallation | undefined,
  ): Promise<readonly MarketplacePlan[]> =>
    typeof options.plans === "function"
      ? options.plans({ productId, installation })
      : (options.plans ?? []);

  const installationOf = async (id: string): Promise<MarketplaceInstallation> =>
    (await data(marketplace.installation(id))) ??
    fail(
      dbError("not_found", `No installation ${id}`, {
        hint: "MARKETPLACE_INSTALLATION_NOT_FOUND",
      }),
    );

  const resourceOf = async (
    installation: string,
    id: string,
  ): Promise<MarketplaceResource> => {
    const resource = await data(marketplace.resource(installation, id));

    return resource === undefined || resource.status === "deleted"
      ? fail(
          dbError("not_found", `No resource ${id}`, {
            hint: "MARKETPLACE_RESOURCE_NOT_FOUND",
          }),
        )
      : resource;
  };

  const setState = (
    installation: string,
    resource: string,
    state: {
      readonly tenant?: string | undefined;
      readonly tenantCreated?: boolean | undefined;
      readonly secretRefs?: readonly string[];
    },
  ): Promise<unknown> =>
    data(
      call(
        "set_marketplace_resource_state",
        {
          configuration_id: installation,
          external_id: resource,
          tenant: state.tenant ?? null,
          tenant_created: state.tenantCreated ?? null,
          secret_refs: state.secretRefs ?? null,
        },
        () => undefined,
      ),
    );

  const teardown = async (
    installation: MarketplaceInstallation,
    resource: MarketplaceResource,
  ): Promise<void> => {
    await options.resources.deprovision?.({ installation, resource });

    if (resource.tenant !== undefined) {
      await removeTenant({
        installation,
        tenant: resource.tenant,
        created: resource.tenantCreated,
      });
    }

    await data(
      marketplace.deleteResource(
        installation.configurationId,
        resource.externalId,
      ),
    );
  };

  const provision = async (
    installation: MarketplaceInstallation,
    id: string,
    body: Readonly<Record<string, unknown>>,
  ): Promise<Response> => {
    const name = optionalText(body["name"]) ?? id;
    const productId = optionalText(body["productId"]);
    const billingPlanId = optionalText(body["billingPlanId"]);
    const metadata = recordField(body, "metadata");
    const plans = await plansFor(productId, installation);

    const result = await options.resources.provision({
      installation,
      resource: { id, productId, name, metadata, billingPlanId },
      plan: plans.find((plan) => plan.id === billingPlanId),
      environments: VERCEL_ENVIRONMENTS,
    });

    const secrets = secretsOf(result.secrets, "resources.provision");

    const stored = await data(
      marketplace.upsertResource({
        configurationId: installation.configurationId,
        externalId: id,
        name,
        ...(billingPlanId === undefined ? {} : { planId: billingPlanId }),
        metadata: { productId, vercel: metadata },
      }),
    );

    await setState(installation.configurationId, id, {
      tenant: result.tenant,
      tenantCreated:
        result.tenant === undefined
          ? undefined
          : (result.tenantCreated ?? false),
      secretRefs: refsOf(secrets),
    });

    return Response.json(resourceBody(stored, secrets), { status: 201 });
  };

  const routeInstallation = async (
    request: Request,
    id: string,
    claims: Readonly<Record<string, unknown>>,
  ): Promise<Response> => {
    switch (request.method) {
      case "PUT": {
        const body = await bodyOf(request);
        const account = recordField(body, "account");

        const scopes = Array.isArray(body["scopes"])
          ? body["scopes"].filter(
              (scope): scope is string => typeof scope === "string",
            )
          : [];

        const teamId = optionalText(claims["account_id"]);
        const userId = optionalText(claims["user_id"]);

        const installation = await data(
          marketplace.upsertInstallation({
            configurationId: id,
            ...(teamId === undefined ? {} : { teamId }),
            ...(userId === undefined ? {} : { userId }),
            metadata: {
              account,
              scopes,
              acceptedPolicies: recordField(body, "acceptedPolicies"),
            },
          }),
        );

        const token = optionalText(
          recordField(body, "credentials")["access_token"],
        );

        if (token !== undefined) {
          await data(marketplace.sealAccessToken(id, token));
        }

        const linked = await options.install?.({
          installation,
          account,
          scopes,
        });

        if (linked?.tenant !== undefined) {
          await data(
            marketplace.linkTenant({
              configurationId: id,
              tenant: linked.tenant,
              created: linked.tenantCreated ?? false,
            }),
          );
        }

        return Response.json({});
      }

      case "GET": {
        const installation = await installationOf(id);
        const plan = optionalText(installation.metadata["billingPlanId"]);

        return Response.json(
          plan === undefined ? {} : { billingPlan: { id: plan } },
        );
      }

      case "PATCH": {
        const body = await bodyOf(request);
        await installationOf(id);
        const plan = optionalText(body["billingPlanId"]);
        await data(
          marketplace.upsertInstallation({
            configurationId: id,
            metadata: plan === undefined ? {} : { billingPlanId: plan },
          }),
        );

        return Response.json({});
      }

      case "DELETE": {
        const installation = await installationOf(id);

        for (const resource of await data(marketplace.resources(id))) {
          await teardown(installation, resource);
        }

        const removed =
          (await data(marketplace.removeInstallation(id))) ?? installation;

        if (removed.tenant !== undefined) {
          await removeTenant({
            installation: removed,
            tenant: removed.tenant,
            created: removed.tenantCreated,
          });
        }

        return Response.json({ finalized: true });
      }

      default: {
        return methodNotAllowed(["PUT", "GET", "PATCH", "DELETE"]);
      }
    }
  };

  const routeResource = async (
    request: Request,
    installation: MarketplaceInstallation,
    id: string,
  ): Promise<Response> => {
    const configurationId = installation.configurationId;

    switch (request.method) {
      case "PUT": {
        return provision(installation, id, await bodyOf(request));
      }

      case "GET": {
        return Response.json(
          resourceBody(await resourceOf(configurationId, id)),
        );
      }

      case "PATCH": {
        const body = await bodyOf(request);
        const resource = await resourceOf(configurationId, id);
        const name = optionalText(body["name"]);
        const billingPlanId = optionalText(body["billingPlanId"]);

        const metadata = isRecord(body["metadata"])
          ? body["metadata"]
          : undefined;

        await options.resources.update?.({
          installation,
          resource,
          changes: {
            ...(name === undefined ? {} : { name }),
            ...(metadata === undefined ? {} : { metadata }),
            ...(billingPlanId === undefined ? {} : { billingPlanId }),
          },
        });

        const updated = await data(
          marketplace.upsertResource({
            configurationId,
            externalId: id,
            name: name ?? resource.name,
            ...(billingPlanId === undefined ? {} : { planId: billingPlanId }),
            status: resource.status,
            metadata: metadata === undefined ? {} : { vercel: metadata },
          }),
        );

        return Response.json(resourceBody(updated));
      }

      case "DELETE": {
        await teardown(installation, await resourceOf(configurationId, id));

        return new Response(null, { status: 204 });
      }

      default: {
        return methodNotAllowed(["PUT", "GET", "PATCH", "DELETE"]);
      }
    }
  };

  const rotate = async (
    request: Request,
    installation: MarketplaceInstallation,
    id: string,
  ): Promise<Response> => {
    const body = await bodyOf(request);
    const resource = await resourceOf(installation.configurationId, id);
    const hooks = options.resources;

    if (hooks.rotate === undefined) {
      return fail(
        dbError("unsupported", "This integration does not rotate secrets", {
          hint: "MARKETPLACE_ROTATE_UNSUPPORTED",
        }),
      );
    }

    const delay = body["delayOldSecretsExpirationHours"];

    const rotated = await hooks.rotate({
      installation,
      resource,
      reason: optionalText(body["reason"]),
    });

    const secrets = secretsOf(rotated.secrets, "resources.rotate");
    await setState(installation.configurationId, id, {
      secretRefs: refsOf(secrets),
    });

    if (hooks.revoke !== undefined && resource.secretRefs.length > 0) {
      await hooks.revoke({
        installation,
        resource,
        previous: resource.secretRefs,
        delayHours: typeof delay === "number" ? delay : undefined,
      });
    }

    return Response.json({ sync: true, secrets: publicSecrets(secrets) });
  };

  const route = async (
    request: Request,
    path: readonly string[],
    claims: Readonly<Record<string, unknown>>,
  ): Promise<Response> => {
    const [root, id, child, resourceId, sub, action] = path;

    if (
      root === "products" &&
      id !== undefined &&
      child === "plans" &&
      path.length === 3
    ) {
      return request.method === "GET"
        ? Response.json({ plans: await plansFor(id, undefined) })
        : methodNotAllowed(["GET"]);
    }

    if (root !== "installations" || id === undefined) {
      return fail(dbError("not_found", "No such Partner API route"));
    }

    if (claims["installation_id"] !== id) {
      return fail(
        dbError("forbidden", "The token was issued for another installation", {
          hint: "MARKETPLACE_INSTALLATION_MISMATCH",
        }),
      );
    }

    if (child === undefined) {
      return routeInstallation(request, id, claims);
    }

    const installation = await installationOf(id);

    if (child === "plans" && path.length === 3) {
      return request.method === "GET"
        ? Response.json({ plans: await plansFor(undefined, installation) })
        : methodNotAllowed(["GET"]);
    }

    if (child !== "resources") {
      return fail(dbError("not_found", "No such Partner API route"));
    }

    if (resourceId === undefined) {
      return request.method === "POST"
        ? provision(installation, newId(), await bodyOf(request))
        : methodNotAllowed(["POST"]);
    }

    if (sub === undefined) {
      return routeResource(request, installation, resourceId);
    }

    if (sub === "secrets" && action === "rotate" && path.length === 6) {
      return request.method === "POST"
        ? rotate(request, installation, resourceId)
        : methodNotAllowed(["POST"]);
    }

    return fail(dbError("not_found", "No such Partner API route"));
  };

  return async (request) => {
    const url = new URL(request.url);
    const instance = url.pathname;

    try {
      const start = url.pathname.indexOf("/v1/");

      if (start === -1) {
        return fail(dbError("not_found", "No such Partner API route"));
      }

      const authorization = request.headers.get("authorization") ?? "";
      const token = /^Bearer\s+(.+)$/iu.exec(authorization)?.[1];

      if (token === undefined) {
        return fail(
          dbError("unauthorized", "Vercel's OIDC token is missing", {
            code: "MISSING_CREDENTIALS",
          }),
        );
      }

      const verified = await deps.verifyToken(token.trim());

      if (!verified.ok) {
        return fail(verified.error);
      }

      const path = url.pathname
        .slice(start + "/v1/".length)
        .split("/")
        .filter((segment) => segment !== "")
        .map((segment) => decodeURIComponent(segment));

      return await route(request, path, verified.data);
    } catch (cause) {
      const error =
        cause instanceof Answer
          ? cause.error
          : (dbErrorOf(cause) ?? dbError("unexpected", errorText(cause)));

      return problemResponse(error, {
        instance,
        realm: "vercel-marketplace",
        format: options.problem,
        ...(options.expose === undefined ? {} : { expose: options.expose }),
      });
    }
  };
}
