import type { IntegrationName } from "../config/types/tooling.ts";

import { INTEGRATION_INFO, INTEGRATION_NAMES } from "../config/names.ts";

/**
 * How `/create` and `init` show one value: its label and, where the label is
 * not enough, a hint.
 */
export interface PresetValueInfo {
  readonly label: string;
  readonly hint?: string;
}

/**
 * One convention a preset sets. `values` and the field list are append-only: a
 * code stores each value's index in `bits` bits, so a value keeps its index
 * forever and a new value fits only while `values` stays within `bits`. A
 * `multi` field stores one bit per value.
 */
export interface PresetCodeField<
  K extends string = string,
  V extends string = string,
> {
  readonly key: K;
  readonly values: readonly V[];
  readonly default: V | readonly V[];
  readonly bits: number;
  readonly multi?: true;
  /**
   * The code version that added the field; older codes decode it as its
   * default.
   */
  readonly since: number;
}

/** A convention field with the names `/create` and the `init` prompts show. */
export interface PresetField<
  K extends string = string,
  V extends string = string,
> extends PresetCodeField<K, V> {
  readonly label: string;
  readonly labels: { readonly [P in V]: PresetValueInfo };
}

/** The value each convention field takes. */
export interface PresetConventions {
  readonly framework: PresetFramework;
  readonly platforms: "web" | "native" | "both";
  readonly casing: "snake" | "camel";
  readonly idType: "uuid" | "text" | "bigint" | "integer";
  readonly scope: "tenant" | "user" | "none";
  readonly tenantName: PresetTenantName;
  readonly access: "roles" | "catalog" | "provider" | "custom";
  readonly api: "none" | "api";
  readonly integrations: readonly IntegrationName[];
}

/** A convention field's key. */
export type PresetFieldKey = keyof PresetConventions;

/** The values a convention field takes. */
export type PresetFieldValue<K extends PresetFieldKey> = ValueOf<K>;

type ValueOf<K extends PresetFieldKey> =
  PresetConventions[K] extends readonly (infer V extends string)[]
    ? V
    : Extract<PresetConventions[K], string>;

/** Types a field's values against `PresetConventions`. */
function field<K extends PresetFieldKey>(
  definition: PresetField<K, ValueOf<K>>,
): PresetField<K, ValueOf<K>> {
  return definition;
}

function integrationLabel(name: IntegrationName): PresetValueInfo {
  const { title, description } = INTEGRATION_INFO[name];

  return { label: title, hint: description };
}

/**
 * The tenant names a preset can set (`blocks.tenant.names.organization`), in
 * code order.
 */
export const PRESET_TENANT_NAMES = [
  "organization",
  "workspace",
  "team",
] as const;

export type PresetTenantName = (typeof PRESET_TENANT_NAMES)[number];

/** The frameworks `/create` and `init --preset` set up glue for. */
export const PRESET_FRAMEWORKS = [
  "next",
  "vite",
  "tanstack-start",
  "expo",
  "sveltekit",
  "nuxt",
  "hono",
  "astro",
  "react-router",
] as const;

export type PresetFramework = (typeof PRESET_FRAMEWORKS)[number];

/**
 * The convention fields, in code order. Append new fields at the end with the
 * next `since`, and never remove or reorder one.
 */
export const PRESET_FIELDS: readonly PresetField<PresetFieldKey>[] = [
  field({
    key: "framework",
    label: "Framework",
    values: PRESET_FRAMEWORKS,
    labels: {
      next: { label: "Next.js" },
      vite: { label: "Vite" },
      "tanstack-start": { label: "TanStack Start" },
      expo: { label: "Expo" },
      sveltekit: { label: "SvelteKit" },
      nuxt: { label: "Nuxt" },
      hono: { label: "Hono" },
      astro: { label: "Astro" },
      "react-router": { label: "React Router" },
    },
    default: "next",
    bits: 5,
    since: 1,
  }),
  field({
    key: "platforms",
    label: "Platforms",
    values: ["web", "native", "both"],
    labels: {
      web: { label: "Web" },
      native: { label: "Native" },
      both: { label: "Web and native" },
    },
    default: "web",
    bits: 2,
    since: 1,
  }),
  field({
    key: "casing",
    label: "Casing",
    values: ["snake", "camel"],
    labels: {
      snake: { label: "snake_case", hint: "Rows keep the database names." },
      camel: {
        label: "camelCase",
        hint: "Rows are renamed inside the PostgREST query.",
      },
    },
    default: "snake",
    bits: 2,
    since: 1,
  }),
  field({
    key: "idType",
    label: "ID type",
    values: ["uuid", "text", "bigint", "integer"],
    labels: {
      uuid: { label: "UUID" },
      text: { label: "Text" },
      bigint: { label: "Bigint" },
      integer: { label: "Integer" },
    },
    default: "uuid",
    bits: 3,
    since: 1,
  }),
  field({
    key: "scope",
    label: "Row ownership",
    values: ["tenant", "user", "none"],
    labels: {
      tenant: {
        label: "Per tenant",
        hint: "Rows belong to a tenant, checked through access.",
      },
      user: { label: "Per user", hint: "Rows belong to the signed-in user." },
      none: {
        label: "Shared",
        hint: "One shared space for every signed-in user.",
      },
    },
    default: "tenant",
    bits: 2,
    since: 1,
  }),
  // `blocks.tenant.names.organization`. New names go at the end.
  field({
    key: "tenantName",
    label: "Tenant name",
    values: PRESET_TENANT_NAMES,
    labels: {
      organization: { label: "Organization" },
      workspace: { label: "Workspace" },
      team: { label: "Team" },
    },
    default: "organization",
    bits: 3,
    since: 1,
  }),
  field({
    key: "access",
    label: "Auth and permissions",
    values: ["roles", "catalog", "provider", "custom"],
    labels: {
      roles: {
        label: "Built-in roles",
        hint: "Owner, admin, member and viewer, mapped to permission keys in the config.",
      },
      catalog: {
        label: "Permissions tables",
        hint: "Role, permission and override tables in the database.",
      },
      provider: {
        label: "Your own provider",
        hint: "Any library that implements AuthorizationProvider.",
      },
      custom: { label: "Custom SQL", hint: "Your own SQL expressions." },
    },
    default: "roles",
    bits: 3,
    since: 1,
  }),
  field({
    key: "api",
    label: "API schema",
    values: ["none", "api"],
    labels: {
      none: {
        label: "Module schema only",
        hint: "The Data API reaches no module tables.",
      },
      api: {
        label: "Data API schema (api)",
        hint: "Security invoker wrappers in an api schema, so the Data API reaches them without exposing the module schema.",
      },
    },
    default: "none",
    bits: 2,
    since: 1,
  }),
  // `INTEGRATION_NAMES`, frozen here: a code stores each one's position.
  field({
    key: "integrations",
    label: "Integrations",
    values: ["next", "hono", "orpc", "edge", "expo", "mcp", "client", "react"],
    labels: {
      next: integrationLabel("next"),
      hono: integrationLabel("hono"),
      orpc: integrationLabel("orpc"),
      edge: integrationLabel("edge"),
      expo: integrationLabel("expo"),
      mcp: integrationLabel("mcp"),
      client: integrationLabel("client"),
      react: integrationLabel("react"),
    },
    default: [],
    bits: 16,
    multi: true,
    since: 1,
  }),
];

/** A convention field by key, with its values and labels typed. */
export function presetField<K extends PresetFieldKey>(
  key: K,
): PresetField<K, ValueOf<K>> {
  const found = PRESET_FIELDS.find((each) => each.key === key);

  if (found === undefined) {
    throw new Error(`Unknown preset field ${key}`);
  }

  // SAFETY: `field()` types every entry's values and labels against its key.
  return found as PresetField<K, ValueOf<K>>;
}

/** A field value's label, or the value itself when it has none. */
export function presetValueLabel(
  key: PresetFieldKey,
  value: string,
): PresetValueInfo {
  const labels: Readonly<Record<string, PresetValueInfo>> =
    presetField(key).labels;

  return (
    (Object.hasOwn(labels, value) ? labels[value] : undefined) ?? {
      label: value,
    }
  );
}

/**
 * The integrations `init --preset` adds for a framework whatever the selection
 * says: the framework's own one, when it has one, then what that one requires.
 */
export function integrationsForFramework(
  framework: PresetFramework,
): readonly IntegrationName[] {
  const own = INTEGRATION_NAMES.find((name) => name === framework);

  return own === undefined ? [] : [own, ...INTEGRATION_INFO[own].requires];
}

export type PresetPlatforms = PresetConventions["platforms"];

export type PresetScope = PresetConventions["scope"];

export type PresetAccess = PresetConventions["access"];

/** A block selection and its conventions: what a preset code encodes. */
export interface Preset extends PresetConventions {
  /**
   * Block names (`blocks` keys in the config), as selected; `resolvePreset`
   * adds what they require.
   */
  readonly blocks: readonly string[];
}

/** The newest code version; `encodePreset` writes it. */
export const PRESET_VERSION = 1;

/** Every convention at its default. */
export const DEFAULT_CONVENTIONS: PresetConventions = {
  framework: "next",
  platforms: "web",
  casing: "snake",
  idType: "uuid",
  scope: "tenant",
  tenantName: "organization",
  access: "roles",
  api: "none",
  integrations: [],
};
