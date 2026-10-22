/* oxlint-disable eslint/no-bitwise -- a 0.14 preset code packs its fields into one bigint bit field. */

import type { CodemodConfigEdit, CodemodResult } from "./codemod.ts";

import { DEFAULT_CONVENTIONS, presetSpec } from "../preset/index.ts";
import { currentBlockName } from "../sql/index.ts";
import { setPresetInConfig, setPresetInJson } from "./sql/config-edit.ts";

/**
 * The 0.14 preset code layout, frozen: the fields in code order with their
 * values and widths, then one bit per block. Codes are no longer written; the
 * 0.15 codemod reads them into a preset object.
 */
const FIELDS: readonly {
  readonly key: string;
  readonly values: readonly string[];
  readonly bits: number;
  readonly multi?: true;
}[] = [
  {
    key: "framework",
    values: [
      "next",
      "vite",
      "tanstack-start",
      "expo",
      "sveltekit",
      "nuxt",
      "hono",
      "astro",
      "react-router",
    ],
    bits: 5,
  },
  { key: "platforms", values: ["web", "native", "both"], bits: 2 },
  { key: "casing", values: ["snake", "camel"], bits: 2 },
  { key: "idType", values: ["uuid", "text", "bigint", "integer"], bits: 3 },
  { key: "scope", values: ["tenant", "user", "none"], bits: 2 },
  { key: "tenantName", values: ["organization", "workspace", "team"], bits: 3 },
  {
    key: "access",
    values: ["roles", "catalog", "provider", "custom"],
    bits: 3,
  },
  { key: "api", values: ["none", "api"], bits: 2 },
  {
    key: "integrations",
    values: ["next", "hono", "orpc", "edge", "expo", "mcp", "client", "react"],
    bits: 16,
    multi: true,
  },
];

/** The 0.14 block bits, in order; `null` marks a removed block. */
const BLOCKS: readonly (string | null)[] = [
  "updated-at",
  "actor",
  "audit",
  "tenant",
  "invitations",
  "reserved-slugs",
  "jobs",
  "idempotency",
  "webhook-inbox",
  "realtime-tables",
  "jsonb-schemas",
  "pgtap",
  "grants",
  "read-sets",
  "mfa",
  "entitlements",
  "rate-limit",
  "vector-search",
  "access",
  "support-sessions",
  "organizations",
  "profiles",
  "outbox",
  "notifications",
  "webhooks-out",
  "sessions",
  "webhooks-in",
  "api-keys",
  "settings",
  "usage",
  "billing",
  "flags",
  "comments",
  "attachments",
  "data-lifecycle",
  "sso",
  "onboarding",
  "waitlist",
  "announcements",
  "streams",
  "credentials",
  "workflows",
  "workflow-sdk-world",
  "workflow-builder",
  "chat-sdk-state",
  "inbox",
  "ai-chat",
  "ai-files",
  "knowledge",
  "memory",
  "agents",
  "connectors",
  "ai-tasks",
  "push",
  "ai-cache",
  "ai-providers",
  "number-sequences",
  "teams",
  "tags",
  "state-machine",
  "custom-fields",
  "share-links",
  "reminders",
  "imports",
  "subjects",
  "rank",
  "saved-views",
  "relations",
  "bulk",
  "search",
  "metrics",
  "calendar",
  "bookings",
  "versions",
  "trash",
  "reactions",
  "approvals",
  "access-requests",
  "documents",
  "catalog",
  "inventory",
  "drive",
  "drive-files",
  "orders",
  "promotions",
  "forms",
  "signatures",
  "time-tracking",
  "identities",
  "service-principals",
  "templates",
  "pipelines",
  "parties",
  "engagements",
  "deals",
  "work-items",
  "quotes",
  "invoices",
  "sla",
  "targets",
  "hiring",
  "employees",
  "collections",
  "ensure-rls",
  "signing-keys",
  "shared-signals",
  "oauth-server",
  "domains",
  "reviews",
  "leave",
  "rules",
  "vercel-marketplace",
  "ledger",
  "assets",
  "scores",
  "moderation",
  "enrollments",
  "guests",
  "passes",
  "billable-time",
  "leases",
  "expenses",
  "donations",
  "dispatch",
  "shipments",
  "contracts",
  "controls",
  "incidents",
  "courses",
  "messaging",
  "channels",
  "activity",
  "mail-sync",
  "segments",
  "assignment",
  "enrichment",
  "forecasts",
  "field-history",
  "sequences",
  "lead-scoring",
  "posts",
  "field-encryption",
];

const BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

/** Whether `value` reads as a 0.14 preset code: `1` and base62 digits. */
export function isLegacyPresetCode(value: string): boolean {
  return /^1[0-9A-Za-z]+$/.test(value);
}

/**
 * The conventions and blocks a 0.14 preset code holds, the blocks under their
 * 0.15 names. Throws a TypeError when `code` isn't one.
 */
export function decodeLegacyPresetCode(code: string): {
  readonly [key: string]: string | readonly string[];
} {
  if (!isLegacyPresetCode(code)) {
    throw new TypeError(`"${code}" is not a 0.14 preset code.`);
  }

  let value = 0n;

  for (const char of code.slice(1)) {
    value = value * 62n + BigInt(BASE62.indexOf(char));
  }

  const preset: Record<string, string | readonly string[]> = {};

  for (const field of FIELDS) {
    const bits = value & ((1n << BigInt(field.bits)) - 1n);
    value >>= BigInt(field.bits);

    if (field.multi === true) {
      preset[field.key] = field.values.filter(
        (_, index) => ((bits >> BigInt(index)) & 1n) === 1n,
      );
      continue;
    }

    const each = field.values[Number(bits)];

    if (each === undefined) {
      throw new TypeError(`Preset code "${code}" has an unknown ${field.key}.`);
    }

    preset[field.key] = each;
  }

  const blocks: string[] = [];

  for (let index = 0; value > 0n; index += 1, value >>= 1n) {
    const name = BLOCKS[index];

    if ((value & 1n) === 1n && name !== null && name !== undefined) {
      blocks.push(currentBlockName(name));
    }
  }

  return { ...preset, blocks };
}

/** The preset a 0.14 code holds, as the name or object the config takes. */
function specOfCode(code: string): ReturnType<typeof presetSpec> {
  const { blocks, ...decoded } = decodeLegacyPresetCode(code);

  return presetSpec({
    ...DEFAULT_CONVENTIONS,
    // SAFETY: every key and value comes from the frozen 0.14 layout, which
    // `PresetConventions` still accepts.
    ...(decoded as Partial<typeof DEFAULT_CONVENTIONS>),
    blocks: typeof blocks === "string" ? [blocks] : (blocks ?? []),
  });
}

const PRESET_CODE =
  /(\bpreset\s*:\s*|"preset"\s*:\s*)(["'])((?:https?:\/\/[^"'?]*\?(?:[^"']*&)?preset=)?)(1[0-9A-Za-z]+)([^"']*)\2/;

/**
 * `better-supabase.config.*` with a 0.14 preset code (or a Create URL holding
 * one) in `preset` rewritten to the preset object or name it holds.
 */
export function convertConfigPresetCode(
  source: string,
  json: boolean,
): CodemodConfigEdit {
  const match = PRESET_CODE.exec(source);

  if (match === null || match[5] !== "") {
    return { ok: true, text: source };
  }

  const spec = specOfCode(match[4] ?? "");

  return json ? setPresetInJson(source, spec) : setPresetInConfig(source, spec);
}

/**
 * A 0.14 design file (`{ preset: "<code>", design }`) as a 0.15 one: the design
 * with the preset object inside. Other JSON is returned as it is.
 */
export function convertDesignFile(source: string): CodemodConfigEdit {
  let value: unknown;

  try {
    value = JSON.parse(source);
  } catch {
    return { ok: false, reason: "it isn't valid JSON" };
  }

  if (
    typeof value !== "object" ||
    value === null ||
    !("preset" in value) ||
    !("design" in value) ||
    typeof value.preset !== "string" ||
    typeof value.design !== "object" ||
    value.design === null
  ) {
    return { ok: true, text: source };
  }

  const preset = isLegacyPresetCode(value.preset)
    ? specOfCode(value.preset)
    : value.preset;

  return {
    ok: true,
    text: `${JSON.stringify({ ...value.design, preset }, null, 2)}\n`,
  };
}

/** A design file Create downloaded (`better-supabase.design.json`). */
export const DESIGN_FILE_NAME: RegExp = /(?:^|[\\/])[^\\/]*\.design\.json$/;

const reviewOf = (edit: CodemodConfigEdit) =>
  edit.ok && "review" in edit ? edit.review : [];

/** `edit`, then `convertConfigPresetCode` on its text, with both reviews. */
export function thenConvertPresetCode(
  edit: CodemodConfigEdit,
  json: boolean,
): CodemodConfigEdit {
  if (!edit.ok) {
    return edit;
  }

  const converted = convertConfigPresetCode(edit.text, json);

  return converted.ok
    ? {
        ok: true,
        text: converted.text,
        review: [...reviewOf(edit), ...reviewOf(converted)],
      }
    : converted;
}

/** A codemod's `designFile` rewrite as a result; a refusal is listed for review. */
export function designFileResult(
  source: string,
  rewrite: ((source: string) => CodemodConfigEdit) | undefined,
): CodemodResult {
  if (rewrite === undefined) {
    return { text: source, review: [] };
  }

  const edit = rewrite(source);

  return edit.ok
    ? { text: edit.text, review: reviewOf(edit) }
    : {
        text: source,
        review: [
          {
            line: 1,
            message: `The design file wasn't rewritten: ${edit.reason}`,
          },
        ],
      };
}
