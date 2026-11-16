import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { BulkCallOptions, BulkReport } from "../../core/bulk.ts";
import type { CustomFieldType } from "../../core/contracts/field-formats.ts";
import type {
  CountOptions,
  FacetOptions,
  TenantOption,
} from "../../core/entity-list.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockTenantOptions } from "../shared.ts";
import type { FieldPack } from "./pack.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { bulkItems } from "../../core/bulk.ts";
import {
  entityList,
  foundOrNotFound,
  tenantOrOption,
} from "../../core/entity-list.ts";
import {
  neighborsForIndex,
  rankBetweenResult,
} from "../../core/rank-result.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import { fieldDefinitionListSurface } from "./lists.ts";

export interface CustomFieldsOptions extends BlockTenantOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<CustomFields>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** The packs `installPacks` installs: `blocks.custom-fields.options.packs`. */
  readonly packs?: readonly FieldPack[];
}

/** What `install_field_pack` reports. */
export interface FieldPackInstall {
  readonly pack: string;
  readonly version: number;
  readonly created: number;
  readonly updated: number;
  readonly unchanged: number;
}

/** Reads and writes values of one legal entity (the legal-entities block). */
export interface FieldEntityScope {
  /**
   * The legal entity. Reads return its value where it has one and the
   * organization's value where it doesn't; writes store the entity's value.
   */
  readonly legalEntity?: string;
}

export interface FieldDefinition {
  readonly id: string;
}

export interface FieldDefinitionDetail extends FieldDefinition {
  readonly entity: string;
  readonly key: string;
  readonly label: string;
  /** A `CustomFieldType`, or the value an adopted table stores. */
  readonly type: string;
  readonly required: boolean;
  readonly sensitive: boolean;
  /**
   * Whether values are stored as ciphertext under the tenant's Vault key
   * (`encryptDefinition`). Always `false` without the `field-encryption`
   * block.
   */
  readonly encrypted: boolean;
  /**
   * The rank key, for `reorderDefinition`; absent when definitions aren't
   * ranked.
   */
  readonly rank?: string;
  /** The field pack that installed the definition, if one did. */
  readonly pack?: string;
  readonly packVersion?: number;
  /** When the field was archived; archived fields leave `listDefinitions`. */
  readonly archivedAt?: string;
}

/**
 * One field value in the keyed layout, as `readFields` and `setField` return
 * it.
 */
export interface FieldValue {
  readonly id: string;
  readonly subject: RecordRef;
  readonly key: string;
  readonly label: string;
  /** A `CustomFieldType`, after `blocks.custom-fields.values`. */
  readonly type: string;
  /** The value from the column of its type: text, number, boolean or JSON. */
  readonly value: unknown;
  readonly rank?: string;
  readonly createdAt?: string;
  readonly updatedAt?: string;
}

/** The input of `setField` (keyed layout). */
export interface SetFieldInput {
  readonly key: string;
  readonly label: string;
  readonly type: CustomFieldType;
  /** A JSON value of the type: a string, number, boolean, or JSON for `json`. */
  readonly value: unknown;
  readonly rank?: string;
  /** Fail with `FIELD_EXISTS` when the record already has `key`. */
  readonly ifAbsent?: boolean;
}

/** Every method that takes no definition id acts in the block's `tenant`. */
export interface CustomFields {
  /**
   * One entity's definitions in the tenant, in display order. Needs
   * `custom_fields.read`.
   */
  /**
   * One keyset page of the tenant's definitions in display order. `filters`
   * takes `entity`, `type`, `sensitive` and `archived`; `q` matches the key and
   * label. It needs the normalized layout (ADR 1077).
   */
  page(
    options?: PageOptions & TenantOption,
  ): AsyncResult<ListPage<FieldDefinitionDetail>>;
  /** Counts per `entity` or `type` for the page's `q` and filters. */
  facets(
    options?: FacetOptions & TenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many definitions match the page's `q` and filters. */
  count(options?: CountOptions & TenantOption): AsyncResult<Count>;
  /** One definition, or a `not_found` error. */
  getDefinition(id: string): AsyncResult<FieldDefinitionDetail>;
  /** @deprecated Use `page` (ADR 1077). */
  listDefinitions(
    entity:
      | string
      | { readonly entity: string; readonly includeArchived?: boolean },
  ): AsyncResult<FieldDefinitionDetail[]>;
  /** Adds or updates the definition of `key` on `entity`. */
  saveDefinition(input: {
    entity: string;
    key: string;
    label: string;
    type: CustomFieldType;
    sensitive?: boolean | undefined;
  }): AsyncResult<FieldDefinition>;
  /**
   * Archives a field: it leaves `listDefinitions`, and `saveDefinition` and
   * `setValue` refuse it with `CUSTOM_FIELD_ARCHIVED`. Its values stay and stay
   * readable. Needs `custom_fields.manage`.
   */
  archiveDefinition(id: string): AsyncResult<FieldDefinition>;
  /** Brings an archived field back. Needs `custom_fields.manage`. */
  restoreDefinition(id: string): AsyncResult<FieldDefinition>;
  /**
   * Deletes a field for good with every value stored under it. Needs the
   * `purge` permission, which falls back to `custom_fields.manage`.
   */
  purgeDefinition(id: string): AsyncResult<boolean>;
  /**
   * Stores a `text`, `email` or `url` field's values as ciphertext from now on
   * and encrypts the ones it has. Needs `custom_fields.manage` and the
   * `field-encryption` block; there is no way back.
   */
  encryptDefinition(id: string): AsyncResult<boolean>;
  /**
   * Moves a definition between the definitions with rank keys `previous` and
   * `next`. Resolves to its new key.
   */
  reorderDefinition(input: {
    id: string;
    neighbors: RankNeighbors;
  }): AsyncResult<string>;
  /**
   * Puts a definition at position `toIndex` (0 is first) among `entity`'s
   * definitions and resolves to its new key. It reads `listDefinitions` and
   * calls `reorderDefinition` with the neighbours there.
   */
  moveDefinition(input: {
    id: string;
    entity: string;
    toIndex: number;
  }): AsyncResult<string>;
  /**
   * Installs a field pack in the tenant. A definition is matched by pack and
   * key, so installing a version again changes nothing. Fails with
   * `CUSTOM_FIELD_ENTITY_UNKNOWN` for a subject type that isn't registered and
   * with `CUSTOM_FIELD_PACK_CONFLICT` for a key a definition outside the pack
   * uses. Needs `custom_fields.manage`.
   */
  installPack(pack: FieldPack): AsyncResult<FieldPackInstall>;
  /** Installs each pack of `options.packs`, in order. */
  installPacks(): AsyncResult<FieldPackInstall[]>;
  /** The custom field values set on `subject`. */
  readValues(input: {
    subject: RecordRef;
    scope?: FieldEntityScope | undefined;
  }): AsyncResult<unknown>;
  /**
   * Sets one custom field value of `subject`. Setting a value again replaces
   * it, so a call never fails on the (subject, field) key.
   */
  setValue(input: {
    subject: RecordRef;
    definitionId: string;
    value: string;
    scope?: FieldEntityScope | undefined;
  }): AsyncResult<FieldDefinition>;
  /**
   * Keyed layout: every field of `subject` as typed rows, in rank order and
   * then by key.
   */
  readFields(subject: RecordRef): AsyncResult<FieldValue[]>;
  /**
   * Keyed layout: sets the field `key` of `subject`, creating it or updating
   * its label, type and value.
   */
  setField(input: {
    subject: RecordRef;
    input: SetFieldInput;
  }): AsyncResult<FieldValue>;
  /**
   * Changes the value of one field value row, keeping its subject and field.
   * Needs `custom_fields.manage`. Fails with `CUSTOM_FIELD_VALUE_NOT_FOUND`
   * and, for a value the field's format refuses, `CUSTOM_FIELD_VALUE_INVALID`.
   */
  updateValue(input: {
    id: string;
    value: string;
  }): AsyncResult<{ id: string }>;
  /** Removes one field value. Needs `custom_fields.manage`. */
  deleteValue(id: string): AsyncResult<boolean>;
  /**
   * `setField` for each input, in order, reported per field key (ADR 1075): a
   * refused field lands in `failed` and the others still run. Takes at most 500
   * inputs, each key once.
   */
  bulkSet(
    input: { subject: RecordRef; inputs: readonly SetFieldInput[] },
    options?: BulkCallOptions,
  ): AsyncResult<BulkReport>;
  /**
   * `setField` for each input, in order. It stops at the first failure.
   *
   * @deprecated Use `bulkSet`, which reports per field and does not stop at the
   * first failure. Removed in 0.70.
   */
  setMany(input: {
    subject: RecordRef;
    inputs: readonly SetFieldInput[];
  }): AsyncResult<FieldValue[]>;
}

function fieldValueOf(value: unknown): FieldValue {
  const row = recordOf(value, "field value");

  const optional = (key: "rank" | "createdAt" | "updatedAt") => {
    const found = optionalText(row[key]);

    return found === undefined ? {} : { [key]: found };
  };

  return {
    id: textOf(row["id"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    key: textOf(row["key"]),
    label: textOf(row["label"]),
    type: textOf(row["type"]),
    value: row["value"] ?? null,
    ...optional("rank"),
    ...optional("createdAt"),
    ...optional("updatedAt"),
  };
}

function fieldPackInstallOf(value: unknown): FieldPackInstall {
  const row = recordOf(value, "install_field_pack");

  return {
    pack: textOf(row["pack"]),
    version: Number(row["version"]),
    created: Number(row["created"]),
    updated: Number(row["updated"]),
    unchanged: Number(row["unchanged"]),
  };
}

/** The argument only a database with the legal-entities block takes. */
function entityArg(scope: FieldEntityScope | undefined) {
  return scope?.legalEntity === undefined
    ? {}
    : { legal_entity: scope.legalEntity };
}

function definitionOf(row: Record<string, unknown>): FieldDefinitionDetail {
  const rank = optionalText(row["rank"]);
  const pack = optionalText(row["pack"]);
  const packVersion = row["packVersion"];
  const archivedAt = optionalText(row["archivedAt"]);

  return {
    id: textOf(row["id"]),
    entity: textOf(row["entity"]),
    key: textOf(row["key"]),
    label: textOf(row["label"]),
    type: textOf(row["type"]),
    required: row["required"] === true,
    sensitive: row["sensitive"] === true,
    encrypted: row["encrypted"] === true,
    ...(rank === undefined ? {} : { rank }),
    ...(pack === undefined ? {} : { pack }),
    ...(typeof packVersion === "number" ? { packVersion } : {}),
    ...(archivedAt === undefined ? {} : { archivedAt }),
  };
}

export function createCustomFields(options: CustomFieldsOptions): CustomFields {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const idOf = (label: string) => (value: unknown) => ({
    id: textOf(recordOf(value, label)["id"]),
  });

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const definitions = entityList<FieldDefinitionDetail, TenantOption>({
    entity: "field definition",
    surface: fieldDefinitionListSurface,
    call,
    tenant: tenantOrOption(options.tenant),
    fn: "page_field_definitions",
    rowOf: (row) => definitionOf(row),
  });

  const client: CustomFields = {
    page: definitions.page,
    facets: definitions.facets,
    count: definitions.count,
    getDefinition: (id) =>
      call("get_field_definition", { id }, (value) =>
        isRecord(value) ? definitionOf(value) : undefined,
      ).andThen((definition) =>
        foundOrNotFound("field definition", definition, id),
      ),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated method stays an alias until 0.70 (ADR 1077)
    listDefinitions: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "list_field_definitions",
          {
            tenant: organizationId,
            entity: typeof input === "string" ? input : input.entity,
            include_archived:
              typeof input === "string"
                ? false
                : (input.includeArchived ?? false),
          },
          (value) =>
            recordsOf(value, "list_field_definitions").map(definitionOf),
        ),
      ),
    saveDefinition: ({ entity, key, label, type, sensitive }) =>
      tenant().andThen((organizationId) =>
        call(
          "save_field_definition",
          {
            tenant: organizationId,
            entity,
            key,
            label,
            type,
            sensitive: sensitive ?? false,
          },
          idOf("save_field_definition"),
        ),
      ),
    reorderDefinition: ({ id, neighbors }) => {
      const key = rankBetweenResult(neighbors);

      if (!key.ok) {
        return AsyncResult.err(key.error);
      }

      return call(
        "rank_field_definition",
        { definition: id, rank: key.data },
        () => key.data,
      );
    },
    moveDefinition: ({ id, entity, toIndex }) =>
      // oxlint-disable-next-line typescript/no-deprecated -- the deprecated method stays an alias until 0.70 (ADR 1077)
      hooked.listDefinitions(entity).andThen((definitions) => {
        const neighbors = neighborsForIndex(definitions, id, toIndex);

        return neighbors.ok
          ? hooked.reorderDefinition({ id, neighbors: neighbors.data })
          : AsyncResult.err(neighbors.error);
      }),
    archiveDefinition: (id) =>
      call(
        "archive_field_definition",
        { definition: id },
        idOf("archive_field_definition"),
      ),
    restoreDefinition: (id) =>
      call(
        "restore_field_definition",
        { definition: id },
        idOf("restore_field_definition"),
      ),
    purgeDefinition: (id) =>
      call(
        "purge_field_definition",
        { definition: id },
        (value) => value === true,
      ),
    encryptDefinition: (id) =>
      call(
        "encrypt_field_definition",
        { definition: id },
        (value) => value === true,
      ),
    installPack: (pack) =>
      tenant().andThen((organizationId) =>
        call(
          "install_field_pack",
          { tenant: organizationId, pack },
          fieldPackInstallOf,
        ),
      ),
    installPacks: () => {
      const results: FieldPackInstall[] = [];
      let chain: AsyncResult<unknown> = AsyncResult.ok(undefined);

      for (const pack of options.packs ?? []) {
        chain = chain.andThen(() =>
          client.installPack(pack).map((installed) => {
            results.push(installed);

            return installed;
          }),
        );
      }

      return chain.map(() => results);
    },
    readValues: ({ subject, scope }) =>
      tenant().andThen((organizationId) =>
        call(
          "read_field_values",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            ...entityArg(scope),
          },
          (value) => value,
        ),
      ),
    setValue: ({ subject, definitionId, value, scope }) =>
      tenant().andThen((organizationId) =>
        call(
          "set_field_value",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            definition: definitionId,
            value,
            ...entityArg(scope),
          },
          idOf("set_field_value"),
        ),
      ),
    readFields: (subject) =>
      tenant().andThen((organizationId) =>
        call(
          "read_field_values",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
          },
          (value) => (Array.isArray(value) ? value : []).map(fieldValueOf),
        ),
      ),
    setField: ({ subject, input }) =>
      tenant().andThen((organizationId) =>
        call(
          "set_field_value",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            key: input.key,
            label: input.label,
            type: input.type,
            value: input.value ?? null,
            rank: input.rank ?? null,
            if_absent: input.ifAbsent ?? false,
          },
          fieldValueOf,
        ),
      ),
    updateValue: ({ id, value }) =>
      call(
        "update_field_value",
        { value_id: id, value },
        idOf("update_field_value"),
      ),
    deleteValue: (id) =>
      call("delete_field_value", { value_id: id }, (value) => value === true),
    bulkSet: ({ subject, inputs }, bulkOptions) =>
      bulkItems(
        inputs.map((input) => ({ id: input.key, input })),
        ({ input }) => hooked.setField({ subject, input }),
        bulkOptions,
      ),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1075)
    setMany: ({ subject, inputs }) =>
      AsyncResult.from(async () => {
        const values: FieldValue[] = [];

        for (const input of inputs) {
          const value = await hooked.setField({ subject, input });

          if (!value.ok) {
            return value;
          }

          values.push(value.data);
        }

        return ok(values);
      }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: CustomFields = withBlockHooks(client, options.hooks, {
    block: "custom-fields",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
