import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

const LEGAL_BASES = [
  "consent",
  "contract",
  "legal_obligation",
  "vital_interest",
  "public_task",
  "legitimate_interest",
] as const;

const STATUSES = ["granted", "refused", "withdrawn", "expired"] as const;

const GIVEN_BY = ["self", "representative"] as const;

/** The lawful basis a purpose names (GDPR Art. 6(1)). */
export type LegalBasis = (typeof LEGAL_BASES)[number];

/** Where a consent stands. Only a granted one that hasn't expired is active. */
export type ConsentStatus = (typeof STATUSES)[number];

/** Who decided: the data subject or a representative. */
export type ConsentGivenBy = (typeof GIVEN_BY)[number];

/** Something an organization asks consent for, in one version. */
export interface ConsentPurpose {
  readonly id: string;
  /** Null for a system purpose every organization uses. */
  readonly organizationId: string | null;
  readonly key: string;
  readonly title: string;
  readonly description?: string;
  readonly legalBasis: LegalBasis;
  readonly version: string;
  /** Granting needs a signature as evidence. */
  readonly requiresSignature: boolean;
  /** How many months a grant lasts; unlimited when left out. */
  readonly validMonths?: number;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt?: Temporal.Instant;
}

export interface ConsentPurposeInput {
  /** Lowercase letters, digits, `_`, `-` and `.`, such as `marketing.email`. */
  readonly key: string;
  readonly title: string;
  /** Default `"1"`. A new version asks every record again. */
  readonly version?: string;
  readonly description?: string;
  /** Default `consent`. */
  readonly legalBasis?: LegalBasis;
  readonly requiresSignature?: boolean;
  /** 1 to 1200. */
  readonly validMonths?: number;
  /**
   * Saves a system purpose every organization uses instead of one of the
   * current organization; service role only.
   */
  readonly system?: boolean;
}

/** One decision on a purpose for a record. */
export interface Consent {
  readonly id: string;
  readonly organizationId: string;
  readonly purposeId: string;
  readonly purposeKey: string;
  readonly purposeTitle: string;
  readonly purposeVersion: string;
  readonly legalBasis: LegalBasis;
  readonly subject: RecordRef;
  readonly givenBy: ConsentGivenBy;
  /** The contact person who decided, when a representative did. */
  readonly givenByContactId?: string;
  /** The user who recorded the decision. */
  readonly givenByUserId?: string;
  readonly status: ConsentStatus;
  /** What the consent covers within the purpose, such as channels. */
  readonly scope: Readonly<Record<string, unknown>>;
  /** When the decision was made, for a refusal too. */
  readonly grantedAt: Temporal.Instant;
  readonly validUntil?: Temporal.Instant;
  readonly withdrawnAt?: Temporal.Instant;
  readonly withdrawnReason?: string;
  readonly signatureId?: string;
  readonly submissionId?: string;
  readonly attachmentId?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  /** Granted and not past `validUntil`. */
  readonly active: boolean;
}

/** The signature, form submission or file that backs a decision. */
export interface ConsentEvidence {
  readonly signatureId?: string;
  readonly submissionId?: string;
  readonly attachmentId?: string;
}

export interface RecordConsentInput {
  readonly subject: RecordRef;
  readonly purposeKey: string;
  readonly status: "granted" | "refused";
  /**
   * Default `self`. A guest who represents the record is always
   * `representative`.
   */
  readonly givenBy?: ConsentGivenBy;
  /** The contact person who decided; required for `representative`. */
  readonly givenByContactId?: string;
  /** Default: now plus the purpose's `validMonths`. */
  readonly validUntil?: Temporal.Instant;
  readonly scope?: Readonly<Record<string, unknown>>;
  readonly evidence?: ConsentEvidence;
}

/** What a consent signal carries: the Sec-GPC header, a TCF string or GPP. */
export type ConsentSignalKind = "gpc" | "tcf" | "gpp";

const SIGNAL_KINDS: readonly ConsentSignalKind[] = ["gpc", "tcf", "gpp"];

/** A signal recorded for a record, with what the database parsed from it. */
export interface ConsentSignal {
  readonly id: string;
  readonly organizationId: string;
  readonly subject: RecordRef;
  readonly kind: ConsentSignalKind;
  /** The value as received. */
  readonly raw: string;
  /**
   * `gpc`: `{ header, optOut, purposeKeys }`. `tcf`: the core segment of the TC
   * string (policy version, language, purposes, special features). `gpp`: the
   * header type and version and the sections as given.
   */
  readonly parsed: Readonly<Record<string, unknown>>;
  /** The consents the signal created or is evidence for. */
  readonly consentIds: readonly string[];
  readonly receivedAt: Temporal.Instant;
}

/** What `recordSignal` takes. */
export interface ConsentSignalInput {
  readonly subject: RecordRef;
  readonly kind: ConsentSignalKind;
  /** `1` for Sec-GPC, the TC string for `tcf`, the GPP string for `gpp`. */
  readonly value: string;
  /** Sec-GPC only: the purposes the signal opts out of. */
  readonly purposeKeys?: readonly string[];
  /** TCF and GPP: the consent the string is evidence for. */
  readonly consentId?: string;
}

/** A consent receipt: the document handed to the person, with its digest. */
export interface ConsentReceipt {
  readonly receiptId: string;
  readonly format: string;
  readonly issuedAt: Temporal.Instant;
  readonly organizationId: string;
  readonly subject: RecordRef;
  readonly purpose: {
    readonly key: string;
    readonly title: string;
    readonly version: string;
    readonly legalBasis: LegalBasis;
  };
  readonly consent: {
    readonly id: string;
    readonly status: ConsentStatus;
    readonly givenBy: ConsentGivenBy;
    readonly grantedAt: Temporal.Instant;
    readonly validUntil?: Temporal.Instant;
    readonly withdrawnAt?: Temporal.Instant;
    readonly scope: Readonly<Record<string, unknown>>;
  };
  readonly evidence: Readonly<Record<string, unknown>>;
  /** The SHA-256 of the receipt's text, in hex. */
  readonly digest: string;
}

export interface Consents {
  /** Creates or changes a purpose version; needs `consents.manage`. */
  savePurpose(input: ConsentPurposeInput): AsyncResult<ConsentPurpose>;
  /** Stops new consents for a purpose; the ones given stay. */
  archivePurpose(purposeId: string): AsyncResult<ConsentPurpose>;
  /** The organization's purposes and the system ones, newest version first. */
  purposes(options?: {
    readonly includeArchived?: boolean;
  }): AsyncResult<readonly ConsentPurpose[]>;
  /**
   * Records a decision on the current version of a purpose. It ends the grant
   * it replaces. Needs `consents.record`, or a guest who is the record or acts
   * for it.
   */
  record(input: RecordConsentInput): AsyncResult<Consent>;
  /** Withdraws a granted consent. */
  withdraw(input: {
    consentId: string;
    reason?: string | undefined;
  }): AsyncResult<Consent>;
  /**
   * Whether the record has a consent in force for the purpose's current
   * version.
   */
  isActive(input: {
    subject: RecordRef;
    purposeKey: string;
  }): AsyncResult<boolean>;
  /** The latest decision per purpose, or every decision with `includeHistory`. */
  list(
    input: { subject: RecordRef } & { readonly includeHistory?: boolean },
  ): AsyncResult<readonly Consent[]>;
  /** Expires the grants past `validUntil`; service role only. Returns how many. */
  expire(): AsyncResult<number>;
  /**
   * Succeeds when the record has an active consent for the purpose, and
   * otherwise fails with a `forbidden` error whose `permission` is
   * `consent:<purposeKey>`.
   */
  require(input: { subject: RecordRef; purposeKey: string }): AsyncResult<true>;
  /**
   * Records a signal as consent evidence. A Sec-GPC signal (`value: "1"`)
   * records a refused consent for each of `purposeKeys`, an opt-out. A TCF v2
   * or GPP string is parsed and kept, optionally tied to a consent. Needs the
   * same access as `record`.
   */
  recordSignal(input: ConsentSignalInput): AsyncResult<ConsentSignal>;
  /** The signals recorded for a record, the newest first. */
  signals(subject: RecordRef): AsyncResult<readonly ConsentSignal[]>;
  /**
   * Issues the receipt for a consent decision. The same consent and status give
   * the same receipt back; a withdrawal gets its own.
   */
  issueReceipt(consentId: string): AsyncResult<ConsentReceipt>;
  /** The receipts of a record's consents, the newest first. */
  receipts(subject: RecordRef): AsyncResult<readonly ConsentReceipt[]>;
}

export interface ConsentsOptions extends BlockOptions {
  readonly hooks?: NoInfer<BlockHooks<Consents>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const optional = <V>(key: string, value: V | undefined): Record<string, V> =>
  value === undefined ? {} : { [key]: value };

function purposeOf(value: unknown, fn: string): ConsentPurpose {
  const row = recordOf(value, fn);
  const months = row["validMonths"];

  return {
    id: textOf(row["id"]),
    organizationId: optionalText(row["organizationId"]) ?? null,
    key: textOf(row["key"]),
    title: textOf(row["title"]),
    legalBasis: enumOrThrow(row["legalBasis"], LEGAL_BASES, "legal basis"),
    version: textOf(row["version"]),
    requiresSignature: row["requiresSignature"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("description", optionalText(row["description"])),
    ...optional(
      "validMonths",
      months === null || months === undefined ? undefined : Number(months),
    ),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
    ...optional("updatedAt", optionalInstant(row["updatedAt"])),
  };
}

function consentOf(value: unknown, fn: string): Consent {
  const row = recordOf(value, fn);
  const text = (key: string): string | undefined => optionalText(row[key]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    purposeId: textOf(row["purposeId"]),
    purposeKey: textOf(row["purposeKey"]),
    purposeTitle: textOf(row["purposeTitle"]),
    purposeVersion: textOf(row["purposeVersion"]),
    legalBasis: enumOrThrow(row["legalBasis"], LEGAL_BASES, "legal basis"),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    givenBy: enumOrThrow(row["givenBy"], GIVEN_BY, "consent giver"),
    status: enumOrThrow(row["status"], STATUSES, "consent status"),
    scope: isRecord(row["scope"]) ? row["scope"] : {},
    grantedAt: requiredInstant(row["grantedAt"], "grantedAt"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    active: row["active"] === true,
    ...optional("givenByContactId", text("givenByContactId")),
    ...optional("givenByUserId", text("givenByUserId")),
    ...optional("validUntil", optionalInstant(row["validUntil"])),
    ...optional("withdrawnAt", optionalInstant(row["withdrawnAt"])),
    ...optional("withdrawnReason", text("withdrawnReason")),
    ...optional("signatureId", text("signatureId")),
    ...optional("submissionId", text("submissionId")),
    ...optional("attachmentId", text("attachmentId")),
    ...optional("createdBy", text("createdBy")),
  };
}

function signalOf(value: unknown, fn: string): ConsentSignal {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    kind: enumOrThrow(row["kind"], SIGNAL_KINDS, "consent signal kind"),
    raw: textOf(row["raw"]),
    parsed: isRecord(row["parsed"]) ? row["parsed"] : {},
    consentIds: (Array.isArray(row["consentIds"]) ? row["consentIds"] : []).map(
      textOf,
    ),
    receivedAt: requiredInstant(row["receivedAt"], "receivedAt"),
  };
}

function receiptOf(value: unknown, fn: string): ConsentReceipt {
  const row = recordOf(value, fn);
  const subject = recordOf(row["subject"], fn);
  const purpose = recordOf(row["purpose"], fn);
  const consent = recordOf(row["consent"], fn);
  const validUntil = optionalInstant(consent["validUntil"]);
  const withdrawnAt = optionalInstant(consent["withdrawnAt"]);

  return {
    receiptId: textOf(row["receiptId"]),
    format: textOf(row["format"]),
    issuedAt: requiredInstant(row["issuedAt"], "issuedAt"),
    organizationId: textOf(row["organizationId"]),
    subject: { type: textOf(subject["type"]), id: textOf(subject["id"]) },
    purpose: {
      key: textOf(purpose["key"]),
      title: textOf(purpose["title"]),
      version: textOf(purpose["version"]),
      legalBasis: enumOrThrow(
        purpose["legalBasis"],
        LEGAL_BASES,
        "legal basis",
      ),
    },
    consent: {
      id: textOf(consent["id"]),
      status: enumOrThrow(consent["status"], STATUSES, "consent status"),
      givenBy: enumOrThrow(consent["givenBy"], GIVEN_BY, "consent giver"),
      grantedAt: requiredInstant(consent["grantedAt"], "grantedAt"),
      scope: isRecord(consent["scope"]) ? consent["scope"] : {},
      ...(validUntil === undefined ? {} : { validUntil }),
      ...(withdrawnAt === undefined ? {} : { withdrawnAt }),
    },
    evidence: isRecord(row["evidence"]) ? row["evidence"] : {},
    digest: textOf(row["digest"]),
  };
}

const evidenceOf = (
  evidence: ConsentEvidence | undefined,
): Record<string, string> =>
  Object.fromEntries(
    Object.entries(evidence ?? {}).filter(
      (entry): entry is [string, string] => typeof entry[1] === "string",
    ),
  );

/**
 * Consent per record and purpose: purposes with their lawful basis and version,
 * decisions with who made them and their evidence, withdrawal and expiry, and
 * `isActive` before processing.
 */
export function createConsents(options: ConsentsOptions): Consents {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const purpose = (fn: string) => (value: unknown) => purposeOf(value, fn);
  const consent = (fn: string) => (value: unknown) => consentOf(value, fn);

  const savePurpose = (
    organizationId: string | null,
    input: ConsentPurposeInput,
  ): AsyncResult<ConsentPurpose> =>
    call(
      "save_consent_purpose",
      {
        tenant: organizationId,
        key: input.key,
        title: input.title,
        version: input.version ?? null,
        description: input.description ?? null,
        legal_basis: input.legalBasis ?? null,
        requires_signature: input.requiresSignature ?? null,
        valid_months: input.validMonths ?? null,
      },
      purpose("save_consent_purpose"),
    );

  const client: Consents = {
    savePurpose: (input) =>
      input.system === true
        ? savePurpose(null, input)
        : tenant().andThen((organizationId) =>
            savePurpose(organizationId, input),
          ),
    archivePurpose: (purposeId) =>
      call(
        "archive_consent_purpose",
        { purpose_id: purposeId },
        purpose("archive_consent_purpose"),
      ),
    purposes: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_consent_purposes",
          {
            tenant: organizationId,
            include_archived: filter.includeArchived ?? false,
          },
          (value) =>
            recordsOf(value, "list_consent_purposes").map(
              purpose("list_consent_purposes"),
            ),
        ),
      ),
    record: (input) =>
      call(
        "record_consent",
        {
          subject_type: input.subject.type,
          subject_id: input.subject.id,
          purpose_key: input.purposeKey,
          status: input.status,
          given_by: input.givenBy ?? "self",
          given_by_contact_id: input.givenByContactId ?? null,
          valid_until:
            input.validUntil === undefined
              ? null
              : instantArg(input.validUntil),
          scope: input.scope ?? {},
          evidence: evidenceOf(input.evidence),
        },
        consent("record_consent"),
      ),
    withdraw: ({ consentId, reason }) =>
      call(
        "withdraw_consent",
        { consent_id: consentId, reason: reason ?? null },
        consent("withdraw_consent"),
      ),
    isActive: ({ subject, purposeKey }) =>
      call(
        "consent_active",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          purpose_key: purposeKey,
        },
        (value) => value === true,
      ),
    list: ({ subject, ...filter }) =>
      call(
        "list_consents",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          include_history: filter.includeHistory ?? false,
        },
        (value) =>
          recordsOf(value, "list_consents").map(consent("list_consents")),
      ),
    expire: () => call("expire_consents", {}, (value) => Number(value ?? 0)),
    require: ({ subject, purposeKey }) =>
      hooked
        .isActive({ subject, purposeKey })
        .andThen((active) =>
          Promise.resolve(
            active
              ? ok(true as const)
              : err(
                  dbError("forbidden", `No active consent for ${purposeKey}`, {
                    permission: `consent:${purposeKey}`,
                  }),
                ),
          ),
        ),
    recordSignal: (input) =>
      call(
        "record_consent_signal",
        {
          subject_type: input.subject.type,
          subject_id: input.subject.id,
          kind: input.kind,
          value: input.value,
          purpose_keys: input.purposeKeys ?? [],
          consent_id: input.consentId ?? null,
        },
        (value) => signalOf(value, "record_consent_signal"),
      ),
    signals: (subject) =>
      call(
        "list_consent_signals",
        { subject_type: subject.type, subject_id: subject.id },
        (value) =>
          recordsOf(value, "list_consent_signals").map((row) =>
            signalOf(row, "list_consent_signals"),
          ),
      ),
    issueReceipt: (consentId) =>
      call("issue_consent_receipt", { consent_id: consentId }, (value) =>
        receiptOf(value, "issue_consent_receipt"),
      ),
    receipts: (subject) =>
      call(
        "list_consent_receipts",
        { subject_type: subject.type, subject_id: subject.id },
        (value) =>
          recordsOf(value, "list_consent_receipts").map((row) =>
            receiptOf(row, "list_consent_receipts"),
          ),
      ),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Consents = withBlockHooks(client, options.hooks, {
    block: "consents",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
