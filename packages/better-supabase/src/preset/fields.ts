import type { IntegrationName } from "../config/types/tooling.ts";

/**
 * One convention a preset sets. `values` and the field list are append-only:
 * a code stores each value's index in `bits` bits, so a value keeps its
 * index forever and a new value fits only while `values` stays within
 * `bits`. A `multi` field stores one bit per value.
 */
export interface PresetField<
  K extends string = string,
  V extends string = string,
> {
  readonly key: K;
  readonly values: readonly V[];
  readonly default: V | readonly V[];
  readonly bits: number;
  readonly multi?: true;
  /** The code version that added the field; older codes decode it as its default. */
  readonly since: number;
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

/** The tenant names a preset can set (`sql.naming.tenant`), in code order. */
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
 * The convention fields, in code order. Append new fields at the end with
 * the next `since`, and never remove or reorder one.
 */
export const PRESET_FIELDS: readonly PresetField<PresetFieldKey>[] = [
  field({
    key: "framework",
    values: PRESET_FRAMEWORKS,
    default: "next",
    bits: 5,
    since: 1,
  }),
  field({
    key: "platforms",
    values: ["web", "native", "both"],
    default: "web",
    bits: 2,
    since: 1,
  }),
  field({
    key: "casing",
    values: ["snake", "camel"],
    default: "snake",
    bits: 2,
    since: 1,
  }),
  field({
    key: "idType",
    values: ["uuid", "text", "bigint", "integer"],
    default: "uuid",
    bits: 3,
    since: 1,
  }),
  field({
    key: "scope",
    values: ["tenant", "user", "none"],
    default: "tenant",
    bits: 2,
    since: 1,
  }),
  // `sql.naming.tenant`. New names go at the end.
  field({
    key: "tenantName",
    values: PRESET_TENANT_NAMES,
    default: "organization",
    bits: 3,
    since: 1,
  }),
  field({
    key: "access",
    values: ["roles", "catalog", "provider", "custom"],
    default: "roles",
    bits: 3,
    since: 1,
  }),
  field({
    key: "api",
    values: ["none", "api"],
    default: "none",
    bits: 2,
    since: 1,
  }),
  // `INTEGRATION_NAMES`, frozen here: a code stores each one's position.
  field({
    key: "integrations",
    values: ["next", "hono", "orpc", "edge", "expo", "mcp", "client", "react"],
    default: [],
    bits: 16,
    multi: true,
    since: 1,
  }),
];

export type PresetPlatforms = PresetConventions["platforms"];

export type PresetScope = PresetConventions["scope"];

export type PresetAccess = PresetConventions["access"];

/** A block selection and its conventions: what a preset code encodes. */
export interface Preset extends PresetConventions {
  /** Block names (`blocks` keys in the config), as selected; `resolvePreset` adds what they require. */
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
