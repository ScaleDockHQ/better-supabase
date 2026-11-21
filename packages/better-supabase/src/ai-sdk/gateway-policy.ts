import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AsyncResult, Result } from "../core/result.ts";
import type { GatewayContext, GatewayOptions } from "./gateway-options.ts";
import type { GatewayGeoRegion } from "./gateway-provider-options.ts";

import { isRecord } from "../core/block-helpers.ts";
import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";
import { gatewayOptions } from "./gateway-options.ts";

/** The regions a policy can pin inference to. */
export const GATEWAY_REGIONS: readonly GatewayGeoRegion[] = [
  "us",
  "eu",
  "au",
  "jp",
];

/**
 * What an organization lets its AI calls do. The AI Gateway has no tenant scope
 * of its own (a team, project, key or member is its smallest unit), so the
 * policy lives in the organization's settings and `governedGatewayOptions`
 * turns it into request options before each call.
 */
export interface GatewayPolicy {
  /** Only route to providers with a zero data retention agreement. */
  readonly zeroDataRetention?: boolean;
  /** Only route to providers that don't train on prompt data. */
  readonly disallowPromptTraining?: boolean;
  /** The only provider slugs the organization's calls may use. */
  readonly allowedProviders?: readonly string[];
  /** Pins inference to a region (regional inference, in beta). */
  readonly region?: GatewayGeoRegion;
  /** Lets the gateway apply the provider's prompt caching (`caching: "auto"`). */
  readonly promptCaching?: boolean;
  /**
   * Provider headquarters as ISO 3166-1 alpha-2 codes, or every code prefixed
   * with `!` to exclude countries. A list can't mix the two.
   */
  readonly headquarters?: readonly string[];
}

/** The settings key `gatewayPolicySetting` is meant for. */
export const GATEWAY_POLICY_KEY = "ai.gateway_policy";

const PROVIDER_SLUG = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const COUNTRY = /^!?[A-Za-z]{2}$/;

const POLICY_KEYS: ReadonlySet<string> = new Set([
  "zeroDataRetention",
  "disallowPromptTraining",
  "allowedProviders",
  "region",
  "promptCaching",
  "headquarters",
]);

function textList(value: unknown): readonly string[] | undefined {
  return Array.isArray(value) && value.every((item) => typeof item === "string")
    ? value
    : undefined;
}

/**
 * Validates a stored policy: unknown keys, a wrong type, a provider that is not
 * a slug, an unknown region or a mixed headquarters list are rejected.
 * `undefined` and `null` read as the empty policy.
 */
export function parseGatewayPolicy(value: unknown): Result<GatewayPolicy> {
  if (value === undefined || value === null) {
    return ok({});
  }

  if (!isRecord(value)) {
    return err(dbError("invalid_input", "A gateway policy is an object."));
  }

  const invalid = (message: string) => err(dbError("invalid_input", message));

  for (const key of Object.keys(value)) {
    if (!POLICY_KEYS.has(key)) {
      return invalid(`Unknown gateway policy key "${key}".`);
    }
  }

  for (const key of [
    "zeroDataRetention",
    "disallowPromptTraining",
    "promptCaching",
  ]) {
    const flag = value[key];

    if (flag !== undefined && typeof flag !== "boolean") {
      return invalid(`${key} is true or false.`);
    }
  }

  const providers = value["allowedProviders"];

  if (providers !== undefined) {
    const list = textList(providers);

    if (list === undefined || list.some((slug) => !PROVIDER_SLUG.test(slug))) {
      return invalid("allowedProviders is a list of provider slugs.");
    }

    if (list.length === 0) {
      return invalid(
        "allowedProviders is empty, so no call could run. Leave it out to allow every provider.",
      );
    }
  }

  const region = value["region"];

  if (
    region !== undefined &&
    !GATEWAY_REGIONS.some((known) => known === region)
  ) {
    return invalid(`region is one of ${GATEWAY_REGIONS.join(", ")}.`);
  }

  const headquarters = value["headquarters"];

  if (headquarters !== undefined) {
    const list = textList(headquarters);

    if (
      list === undefined ||
      list.length === 0 ||
      !list.every((code) => COUNTRY.test(code))
    ) {
      return invalid("headquarters is a list of two-letter country codes.");
    }

    if (new Set(list.map((code) => code.startsWith("!"))).size > 1) {
      return invalid("headquarters can't mix allowed and excluded countries.");
    }
  }

  const policy: {
    -readonly [K in keyof GatewayPolicy]: GatewayPolicy[K];
  } = {};

  for (const key of [
    "zeroDataRetention",
    "disallowPromptTraining",
    "promptCaching",
  ] as const) {
    const flag = value[key];

    if (typeof flag === "boolean") {
      policy[key] = flag;
    }
  }

  const allowed = textList(providers);

  if (allowed !== undefined) {
    policy.allowedProviders = [...allowed];
  }

  if (typeof region === "string") {
    // SAFETY: the check above matched it against GATEWAY_REGIONS.
    policy.region = region as GatewayGeoRegion;
  }

  const countries = textList(headquarters);

  if (countries !== undefined) {
    policy.headquarters = countries.map((code) =>
      code.startsWith("!")
        ? `!${code.slice(1).toUpperCase()}`
        : code.toUpperCase(),
    );
  }

  return ok(policy);
}

/**
 * The policy as a Standard Schema, for `defineSettings`: `defineSettings({
 * organization: { [GATEWAY_POLICY_KEY]: gatewayPolicySetting } })`. A stored
 * value that fails the schema reads as the default, which is the empty policy
 * (no restriction), so keep the key's `settings.update` permission limited to
 * organization admins.
 */
export const gatewayPolicySchema: StandardSchemaV1<unknown, GatewayPolicy> = {
  "~standard": {
    version: 1,
    vendor: "better-supabase",
    validate: (value) => {
      const parsed = parseGatewayPolicy(value);

      if (parsed.ok) {
        return { value: parsed.data };
      }

      return { issues: [{ message: parsed.error.message }] };
    },
  },
};

/**
 * A settings entry for the organization policy, with the empty policy as
 * default.
 */
export const gatewayPolicySetting: {
  readonly schema: StandardSchemaV1<unknown, GatewayPolicy>;
  readonly default: GatewayPolicy;
} = { schema: gatewayPolicySchema, default: {} };

/**
 * Reads an organization's policy: pass a function that reads the settings key,
 * such as `(organizationId) => settings.getOrganization({ organizationId, key:
 * GATEWAY_POLICY_KEY })`. A value that fails validation is an error, not the
 * empty policy, so a call never runs without the restriction an admin set.
 */
export function gatewayPolicyReader(
  read: (organizationId: string) => AsyncResult<unknown>,
): (organizationId: string) => AsyncResult<GatewayPolicy> {
  return (organizationId) =>
    read(organizationId).andThen((value) =>
      Promise.resolve(parseGatewayPolicy(value)),
    );
}

/**
 * Combines the app's baseline policy with an organization's: the result is
 * never looser than either. Flags are or-ed, provider lists are intersected (an
 * empty intersection is an error), and the baseline's region and headquarters
 * win when it sets them.
 */
export function mergeGatewayPolicies(
  base: GatewayPolicy,
  organization: GatewayPolicy,
): Result<GatewayPolicy> {
  const policy: { -readonly [K in keyof GatewayPolicy]: GatewayPolicy[K] } = {};

  for (const key of [
    "zeroDataRetention",
    "disallowPromptTraining",
    "promptCaching",
  ] as const) {
    if (base[key] === true || organization[key] === true) {
      policy[key] = true;
    }
  }

  const a = base.allowedProviders;
  const b = organization.allowedProviders;

  if (a !== undefined && b !== undefined) {
    const both = a.filter((slug) => b.includes(slug));

    if (both.length === 0) {
      return err(
        dbError(
          "invalid_input",
          "The organization's providers and the app's providers have nothing in common.",
        ),
      );
    }

    policy.allowedProviders = both;
  } else if (a !== undefined || b !== undefined) {
    policy.allowedProviders = [...(a ?? b ?? [])];
  }

  const region = base.region ?? organization.region;

  if (region !== undefined) {
    policy.region = region;
  }

  const headquarters = base.headquarters ?? organization.headquarters;

  if (headquarters !== undefined) {
    policy.headquarters = [...headquarters];
  }

  return ok(policy);
}

/**
 * `options` with the policy applied. A policy value always wins over the
 * request's: a flag the policy turns on can't be turned off, `only` becomes the
 * providers both lists allow (a request that names none of the allowed
 * providers is an error, because the gateway would fail it), `order` drops
 * providers outside the policy, and `inferenceRegion` and `headquarters` are
 * replaced. Settings the policy leaves out stay as the request has them.
 */
export function applyGatewayPolicy(
  policy: GatewayPolicy,
  options: GatewayOptions = {},
): Result<GatewayOptions> {
  const next: { -readonly [K in keyof GatewayOptions]: GatewayOptions[K] } = {
    ...options,
  };

  if (policy.zeroDataRetention === true) {
    next.zeroDataRetention = true;
  }

  if (policy.disallowPromptTraining === true) {
    next.disallowPromptTraining = true;
  }

  if (policy.promptCaching === true) {
    next.caching = "auto";
  }

  if (policy.region !== undefined) {
    next.inferenceRegion = { scope: "zone", geoRegion: policy.region };
  }

  if (policy.headquarters !== undefined) {
    next.headquarters = [...policy.headquarters];
  }

  const allowed = policy.allowedProviders;

  if (allowed !== undefined) {
    const only =
      options.only === undefined
        ? [...allowed]
        : options.only.filter((slug) => allowed.includes(slug));

    if (only.length === 0) {
      return err(
        dbError(
          "invalid_input",
          "None of the requested providers is allowed for this organization.",
        ),
      );
    }

    next.only = only;

    if (options.order !== undefined) {
      next.order = options.order.filter((slug) => allowed.includes(slug));
    }
  }

  return ok(next);
}

/**
 * `providerOptions` for a governed call: `gatewayOptions(context, extra)` with
 * the organization's policy applied. Pass the policy `gatewayPolicyReader`
 * loaded. The user and tags still come from `context`.
 */
export function governedGatewayOptions(
  context: GatewayContext,
  policy: GatewayPolicy,
  extra: GatewayOptions = {},
): Result<{ readonly gateway: GatewayOptions }> {
  const { gateway } = gatewayOptions(context, extra);

  const applied = applyGatewayPolicy(policy, gateway);

  return applied.ok ? ok({ gateway: applied.data }) : applied;
}
