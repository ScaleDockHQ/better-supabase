import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  applyTemporal,
  blockCall,
  isRecord,
  nullableText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
  nullableInstant,
} from "../shared.ts";

/** The fiscal calendar of one legal entity. */
export interface LegalEntityFiscal {
  /** The month the fiscal year starts: 1 (January) to 12. */
  readonly fiscalYearStartMonth: number;
  readonly taxPeriod: "monthly" | "quarterly";
}

/** One setting resolved for a legal entity. */
export interface ResolvedSetting {
  readonly source: "legal_entity" | "organization" | "default";
  /** The stored JSON; undefined when `source` is `default`. */
  readonly value: unknown;
  /** The entity the lookup used; undefined when the organization has none. */
  readonly legalEntityId: string | undefined;
}

/** A company that issues invoices and keeps books inside an organization. */
export interface LegalEntity {
  readonly id: string;
  readonly organizationId: string;
  /** Unique per organization, such as `NL01`. */
  readonly code: string;
  readonly name: string;
  readonly address: Readonly<Record<string, unknown>>;
  readonly vatNumber: string | null;
  readonly cocNumber: string | null;
  readonly iban: string | null;
  readonly bic: string | null;
  readonly logoAttachmentId: string | null;
  /** An ISO 4217 code, such as `EUR`. */
  readonly defaultCurrency: string | null;
  readonly fiscal: LegalEntityFiscal;
  /** One per organization: what a null `legal_entity_id` means. */
  readonly isDefault: boolean;
  readonly archivedAt: Temporal.Instant | null;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface LegalEntityInput {
  readonly code?: string;
  readonly name?: string;
  readonly address?: Readonly<Record<string, unknown>>;
  readonly vatNumber?: string | null;
  readonly cocNumber?: string | null;
  readonly iban?: string | null;
  readonly bic?: string | null;
  readonly logoAttachmentId?: string | null;
  readonly defaultCurrency?: string | null;
  readonly fiscal?: Partial<LegalEntityFiscal>;
}

export interface CreateLegalEntityInput extends LegalEntityInput {
  readonly code: string;
  readonly name: string;
  /** Make it the default; the first entity of an organization always is. */
  readonly isDefault?: boolean;
}

export interface LegalEntitiesOptions extends BlockOptions {
  readonly hooks?: NoInfer<BlockHooks<LegalEntities>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/**
 * Legal entities: the companies of an organization, one of them the default,
 * with settings that fall back to the organization's. Reads need
 * `legal_entities.read`, writes `legal_entities.manage`.
 */
export interface LegalEntities {
  /** The first entity of an organization becomes its default. */
  create(input: CreateLegalEntityInput): AsyncResult<LegalEntity>;
  /** Changes the fields present in `input`. */
  update(id: string, input: LegalEntityInput): AsyncResult<LegalEntity>;
  /** Makes an active entity the default; the previous default stops being it. */
  setDefault(id: string): AsyncResult<LegalEntity>;
  /** The default cannot be archived. */
  archive(id: string): AsyncResult<LegalEntity>;
  restore(id: string): AsyncResult<LegalEntity>;
  get(id: string): AsyncResult<LegalEntity>;
  /** The default first, then by code. */
  list(options?: {
    readonly includeArchived?: boolean;
  }): AsyncResult<readonly LegalEntity[]>;
  /**
   * The entity `id` stands for: itself, or the default when `id` is omitted.
   * `undefined` when the organization has no legal entity yet.
   */
  of(id?: string): AsyncResult<string | undefined>;
  /**
   * Where one organization setting comes from for an entity: its own value, the
   * organization's, or neither (`source: "default"`, `value` undefined), so the
   * caller applies the code default. The settings block's `resolve` does that
   * for typed keys.
   */
  resolveSetting(
    key: string,
    options?: { readonly legalEntityId?: string },
  ): AsyncResult<ResolvedSetting>;
  /** The settings stored on this entity, by key, as JSON. */
  settings(id: string): AsyncResult<Readonly<Record<string, unknown>>>;
  setSetting(id: string, key: string, value: unknown): AsyncResult<unknown>;
  /** Removes the entity's value, so the organization's applies again. */
  resetSetting(id: string, key: string): AsyncResult<boolean>;
}

function fiscalOf(value: unknown): LegalEntityFiscal {
  const row = isRecord(value) ? value : {};

  return {
    fiscalYearStartMonth: Number(row["fiscalYearStartMonth"] ?? 1),
    taxPeriod: row["taxPeriod"] === "monthly" ? "monthly" : "quarterly",
  };
}

function legalEntityOf(value: unknown, fn: string): LegalEntity {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    code: textOf(row["code"]),
    name: textOf(row["name"]),
    address: isRecord(row["address"]) ? row["address"] : {},
    vatNumber: nullableText(row["vatNumber"]),
    cocNumber: nullableText(row["cocNumber"]),
    iban: nullableText(row["iban"]),
    bic: nullableText(row["bic"]),
    logoAttachmentId: nullableText(row["logoAttachmentId"]),
    defaultCurrency: nullableText(row["defaultCurrency"]),
    fiscal: fiscalOf(row["fiscal"]),
    isDefault: row["isDefault"] === true,
    archivedAt: nullableInstant(row["archivedAt"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

const PATCH_KEYS: Readonly<Record<keyof LegalEntityInput, string>> = {
  code: "code",
  name: "name",
  address: "address",
  vatNumber: "vat_number",
  cocNumber: "coc_number",
  iban: "iban",
  bic: "bic",
  logoAttachmentId: "logo_attachment_id",
  defaultCurrency: "default_currency",
  fiscal: "fiscal",
};

function patchOf(input: LegalEntityInput): Record<string, unknown> {
  const patch: Record<string, unknown> = {};

  for (const [key, column] of Object.entries(PATCH_KEYS)) {
    // SAFETY: the keys of PATCH_KEYS are the keys of LegalEntityInput.
    const value = input[key as keyof LegalEntityInput];

    if (value !== undefined) {
      patch[column] = value;
    }
  }

  return patch;
}

export function createLegalEntities(
  options: LegalEntitiesOptions,
): LegalEntities {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const one = (fn: string) => (value: unknown) => legalEntityOf(value, fn);

  const client: LegalEntities = {
    create: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_legal_entity",
          {
            tenant: organizationId,
            code: input.code,
            name: input.name,
            address: input.address ?? null,
            vat_number: input.vatNumber ?? null,
            coc_number: input.cocNumber ?? null,
            iban: input.iban ?? null,
            bic: input.bic ?? null,
            logo_attachment_id: input.logoAttachmentId ?? null,
            default_currency: input.defaultCurrency ?? null,
            fiscal: input.fiscal ?? null,
            is_default: input.isDefault ?? false,
          },
          one("create_legal_entity"),
        ),
      ),
    update: (id, input) =>
      call(
        "update_legal_entity",
        { legal_entity_id: id, patch: patchOf(input) },
        one("update_legal_entity"),
      ),
    setDefault: (id) =>
      call(
        "set_default_legal_entity",
        { legal_entity_id: id },
        one("set_default_legal_entity"),
      ),
    archive: (id) =>
      call(
        "set_legal_entity_archived",
        { legal_entity_id: id, archived: true },
        one("set_legal_entity_archived"),
      ),
    restore: (id) =>
      call(
        "set_legal_entity_archived",
        { legal_entity_id: id, archived: false },
        one("set_legal_entity_archived"),
      ),
    get: (id) =>
      call(
        "get_legal_entity",
        { legal_entity_id: id },
        one("get_legal_entity"),
      ),
    list: (listOptions = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_legal_entities",
          {
            tenant: organizationId,
            include_archived: listOptions.includeArchived ?? false,
          },
          (value) =>
            recordsOf(value, "list_legal_entities").map((row) =>
              legalEntityOf(row, "list_legal_entities"),
            ),
        ),
      ),
    of: (id) =>
      tenant().andThen((organizationId) =>
        call(
          "legal_entity_of",
          { tenant: organizationId, id: id ?? null },
          (value) => (value === null ? undefined : textOf(value)),
        ),
      ),
    resolveSetting: (key, resolveOptions) =>
      tenant().andThen((organizationId) =>
        call(
          "resolve_setting",
          {
            tenant: organizationId,
            key,
            legal_entity: resolveOptions?.legalEntityId ?? null,
          },
          (value): ResolvedSetting => {
            const row = recordOf(value, "resolve_setting");
            const source = row["source"];

            return {
              source:
                source === "legal_entity" || source === "organization"
                  ? source
                  : "default",
              value: source === "default" ? undefined : row["value"],
              legalEntityId:
                row["legalEntityId"] === null ||
                row["legalEntityId"] === undefined
                  ? undefined
                  : textOf(row["legalEntityId"]),
            };
          },
        ),
      ),
    settings: (id) =>
      call("get_legal_entity_settings", { legal_entity_id: id }, (value) =>
        isRecord(value) ? value : {},
      ),
    setSetting: (id, key, value) =>
      call(
        "set_legal_entity_setting",
        { legal_entity_id: id, key, value: { value } },
        (stored) => stored,
      ),
    resetSetting: (id, key) =>
      call(
        "reset_legal_entity_setting",
        { legal_entity_id: id, key },
        (removed) => removed === true,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "legal-entities",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
