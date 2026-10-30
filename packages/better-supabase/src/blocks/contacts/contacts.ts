import type { Money } from "../../commerce/money.ts";
import type {
  BlockFields,
  FieldsOf,
  RowFields,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions, CursorPageOptions } from "../shared.ts";
import type {
  RepresentativeAuthority,
  RepresentativeRole,
} from "./representatives.ts";
import type { SupplierStatus } from "./roles.ts";

import {
  blockFields,
  readAllFields,
  readFields,
  writeFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { amountText, optionalMoneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  pageOf,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import {
  REPRESENTATIVE_AUTHORITIES,
  REPRESENTATIVE_ROLES,
} from "./representatives.ts";
import { SUPPLIER_STATUSES } from "./roles.ts";

/** Where a page of a list stops: the last row's name and id. */
export interface PartyCursor {
  readonly name: string;
  readonly id: string;
}

export interface PartyPage<T> {
  readonly items: readonly T[];
  /** Pass as `cursor` for the next page; `undefined` on the last page. */
  readonly next?: PartyCursor;
}

interface PartyRecord {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly lifecycle: string;
  readonly ownerId?: string;
  /** Set when this record was merged into another and archived. */
  readonly mergedInto?: string;
  readonly archived: boolean;
  /** Customer, supplier, funder, partner: `options.roles`, sorted. */
  readonly roles: readonly string[];
  readonly paymentTermsDays?: number;
  readonly creditLimit?: Money;
  /** Where the record stands as a supplier; unset when not assessed. */
  readonly supplierStatus?: SupplierStatus;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: Readonly<Record<string, unknown>>;
}

/** A company or a person, as `setRoles` and `setSupplierStatus` return it. */
export type Party<F extends object = Record<never, never>> =
  | { readonly type: "company"; readonly company: Company<F> }
  | { readonly type: "person"; readonly person: Person };

/** The commercial terms a company or a person takes in a write. */
interface TermsInput {
  /** Days until an invoice is due, 0 to 3650. */
  readonly paymentTermsDays?: number | null;
  /** The credit the organization extends, in minor units with its currency. */
  readonly creditLimit?: Money | null;
}

/** A company. `F` types the extra columns the `fields` schema describes. */
export interface Company<
  F extends object = Record<never, never>,
> extends PartyRecord {
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
  readonly domain?: string;
  readonly website?: string;
  readonly vatId?: string;
  readonly address?: Readonly<Record<string, unknown>>;
}

export interface Person extends PartyRecord {
  readonly email?: string;
  readonly phone?: string;
  readonly title?: string;
  /** The user this person signs in as, for a portal or the inbox widget. */
  readonly userId?: string;
  readonly avatarUrl?: string;
  /** What a channel told about the person, such as an inbox contact's profile. */
  readonly metadata?: Readonly<Record<string, unknown>>;
}

/** A person's address on a channel: an email address, a WhatsApp number. */
export interface PersonIdentity {
  readonly id: string;
  readonly organizationId: string;
  readonly personId: string;
  readonly channel: string;
  readonly address: string;
  readonly verifiedAt?: Temporal.Instant;
  readonly createdAt?: Temporal.Instant;
}

export interface PersonIdentityInput {
  readonly channel: string;
  readonly address: string;
  /** Marks the address verified, now. */
  readonly verified?: boolean;
}

/** A person at a company. */
export interface CompanyPerson extends Person {
  readonly role?: string;
  /** Whether this is the company's primary contact. */
  readonly primary: boolean;
}

/** One `represents` link: a person represents a record. */
export interface Representation {
  /** The relations link's id. */
  readonly id: string;
  readonly organizationId: string;
  readonly personId: string;
  readonly role: RepresentativeRole;
  readonly authority: RepresentativeAuthority;
  readonly validFrom?: Temporal.PlainDate;
  /** The last day the link holds. */
  readonly validUntil?: Temporal.PlainDate;
}

/** A representative of a record, with the person's contact details. */
export interface Representative extends Representation {
  readonly name: string;
  readonly email?: string;
  readonly phone?: string;
  /** Whether the link holds today. */
  readonly active: boolean;
  readonly createdAt?: Temporal.Instant;
}

/** A record the caller represents as a guest. */
export interface RepresentedRecord extends Representation {
  readonly subjectType: string;
  readonly subjectId: string;
}

/**
 * The fields of a write. Left out keeps the stored value; `null` clears it (a
 * name and a lifecycle can't be cleared).
 */
export interface CompanyInput<
  F extends object = Record<never, never>,
> extends TermsInput {
  /** Leave out to create a company; `name` is then required. */
  readonly id?: string;
  readonly name?: string;
  readonly domain?: string | null;
  readonly website?: string | null;
  readonly vatId?: string | null;
  readonly lifecycle?: string;
  readonly ownerId?: string | null;
  readonly address?: Readonly<Record<string, unknown>> | null;
  /**
   * Values for the app's extra columns, by column name; `options.fields` checks
   * them.
   */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export interface PersonInput extends TermsInput {
  /** Leave out to create a person; `name` is then required. */
  readonly id?: string;
  readonly name?: string;
  readonly email?: string | null;
  readonly phone?: string | null;
  readonly title?: string | null;
  readonly lifecycle?: string;
  readonly ownerId?: string | null;
  readonly userId?: string | null;
  readonly fields?: Readonly<Record<string, unknown>>;
}

export interface PartyListOptions extends CursorPageOptions<PartyCursor> {
  /** Matches the name, and a company's domain or a person's email. */
  readonly search?: string;
  readonly lifecycle?: string;
  readonly ownerId?: string;
  /** Keeps the ones with this role. */
  readonly role?: string;
  readonly supplierStatus?: SupplierStatus;
}

export interface Contacts<F extends object = Record<never, never>> {
  saveCompany(
    organizationId: string,
    input: CompanyInput<F>,
  ): AsyncResult<Company<F>>;
  savePerson(organizationId: string, input: PersonInput): AsyncResult<Person>;
  /** Archives a company, or restores it with `archived: false`. */
  archiveCompany(id: string, archived?: boolean): AsyncResult<boolean>;
  archivePerson(id: string, archived?: boolean): AsyncResult<boolean>;
  /**
   * Links a person to a company. `primary` replaces the company's primary
   * contact.
   */
  linkPerson(
    companyId: string,
    personId: string,
    link?: { readonly role?: string; readonly primary?: boolean },
  ): AsyncResult<boolean>;
  unlinkPerson(companyId: string, personId: string): AsyncResult<boolean>;
  /** Merges `drop` into `keep`. Needs `contacts.manage`. */
  mergeCompanies(keep: string, drop: string): AsyncResult<Company<F>>;
  mergePeople(keep: string, drop: string): AsyncResult<Person>;
  /** A page of active companies by name (50 by default, at most 200). */
  listCompanies(
    organizationId: string,
    options?: PartyListOptions,
  ): AsyncResult<PartyPage<Company<F>>>;
  listPeople(
    organizationId: string,
    options?: PartyListOptions,
  ): AsyncResult<PartyPage<Person>>;
  /**
   * Sets a company's or person's roles from `options.roles`, sorted and without
   * duplicates. Needs `contacts.write`.
   */
  setRoles(partyId: string, roles: readonly string[]): AsyncResult<Party<F>>;
  /**
   * Sets where a company or person stands as a supplier, or clears it with
   * `null`. Needs `contacts.approve_supplier`; records
   * `company.supplier_status_changed` or `person.supplier_status_changed` with
   * the reason.
   */
  setSupplierStatus(
    partyId: string,
    status: SupplierStatus | null,
    reason?: string,
  ): AsyncResult<Party<F>>;
  /**
   * The status a company's qualifications give it: `approved` when the gap
   * report lists nothing missing or expired, `conditional` otherwise. Needs the
   * qualifications block.
   */
  supplierStatusFromQualifications(
    companyId: string,
  ): AsyncResult<SupplierStatus>;
  /** A company's people with their role, primary contact first. */
  peopleOf(companyId: string): AsyncResult<CompanyPerson[]>;
  /** A person's addresses on channels, by channel and address. */
  identities(personId: string): AsyncResult<PersonIdentity[]>;
  /**
   * Adds an address on a channel to a person. An address another person of the
   * organization holds fails with `PARTY_IDENTITY_TAKEN`.
   */
  addIdentity(
    personId: string,
    identity: PersonIdentityInput,
  ): AsyncResult<PersonIdentity>;
  /** Removes an identity; `false` when there was none. */
  removeIdentity(identityId: string): AsyncResult<boolean>;
  /** The person an address on a channel belongs to. */
  findByIdentity(
    organizationId: string,
    channel: string,
    address: string,
  ): AsyncResult<Person | undefined>;
  /**
   * The people who represent a record through `represents` links, holding links
   * first. Needs the relations block.
   */
  representativesOf(
    subjectType: string,
    subjectId: string,
  ): AsyncResult<Representative[]>;
  /**
   * The records the caller represents in an organization as a guest whose party
   * is the representative, while the link holds.
   */
  representedByMe(organizationId: string): AsyncResult<RepresentedRecord[]>;
}

export interface ContactsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the extra columns of the companies table
   * (`blocks.contacts.options.extraColumns`): writes are validated, reads
   * parsed.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Contacts<FieldsOf<S>>>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const COMMON = [
  "id",
  "tenant_id",
  "name",
  "lifecycle",
  "owner_user_id",
  "merged_into",
  "roles",
  "payment_terms_days",
  "credit_limit",
  "credit_currency",
  "supplier_status",
  "archived_at",
  "created_by",
  "created_at",
  "updated_at",
];

const COMPANY_COLUMNS = new Set([
  ...COMMON,
  "domain",
  "website",
  "vat_id",
  "address",
]);

const PERSON_COLUMNS = new Set([
  ...COMMON,
  "email",
  "phone",
  "title",
  "user_id",
  "avatar_url",
  "metadata",
  "role",
  "is_primary",
]);

const fieldsOf = (
  row: Record<string, unknown>,
  known: ReadonlySet<string>,
): Record<string, unknown> =>
  Object.fromEntries(Object.entries(row).filter(([key]) => !known.has(key)));

function base(
  row: Record<string, unknown>,
  known: ReadonlySet<string>,
): PartyRecord {
  const fields = row["fields"];
  const ownerId = optionalText(row["owner_user_id"]);
  const mergedInto = optionalText(row["merged_into"]);
  const roles = row["roles"];
  const terms = row["payment_terms_days"];

  const creditLimit = optionalMoneyOf(
    row["credit_limit"],
    row["credit_currency"],
    "credit_limit",
  );

  const status = optionalText(row["supplier_status"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    name: textOf(row["name"]),
    lifecycle: textOf(row["lifecycle"]),
    archived: row["archived_at"] !== null && row["archived_at"] !== undefined,
    roles: Array.isArray(roles) ? roles.map((role) => textOf(role)) : [],
    fields: isRecord(fields) ? fields : fieldsOf(row, known),
    ...(ownerId === undefined ? {} : { ownerId }),
    ...(mergedInto === undefined ? {} : { mergedInto }),
    ...(typeof terms === "number" ? { paymentTermsDays: terms } : {}),
    ...(creditLimit === undefined ? {} : { creditLimit }),
    ...(status === undefined
      ? {}
      : {
          supplierStatus: enumOrThrow(
            status,
            SUPPLIER_STATUSES,
            "supplier status",
          ),
        }),
  };
}

function companyOf(value: unknown): Company {
  const row = recordOf(value, "company");
  const domain = optionalText(row["domain"]);
  const website = optionalText(row["website"]);
  const vatId = optionalText(row["vat_id"]);
  const address = row["address"];

  return {
    ...base(row, COMPANY_COLUMNS),
    ...(domain === undefined ? {} : { domain }),
    ...(website === undefined ? {} : { website }),
    ...(vatId === undefined ? {} : { vatId }),
    ...(isRecord(address) ? { address } : {}),
  };
}

function personOf(value: unknown): Person {
  const row = recordOf(value, "person");
  const email = optionalText(row["email"]);
  const phone = optionalText(row["phone"]);
  const title = optionalText(row["title"]);
  const userId = optionalText(row["user_id"]);
  const avatarUrl = optionalText(row["avatar_url"]);
  const metadata = row["metadata"];

  return {
    ...base(row, PERSON_COLUMNS),
    ...(email === undefined ? {} : { email }),
    ...(phone === undefined ? {} : { phone }),
    ...(title === undefined ? {} : { title }),
    ...(userId === undefined ? {} : { userId }),
    ...(avatarUrl === undefined ? {} : { avatarUrl }),
    ...(isRecord(metadata) ? { metadata } : {}),
  };
}

function identityOf(value: unknown): PersonIdentity {
  const row = recordOf(value, "person identity");
  const verifiedAt = optionalInstant(row["verified_at"]);
  const createdAt = optionalInstant(row["created_at"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    personId: textOf(row["person_id"]),
    channel: textOf(row["channel"]),
    address: textOf(row["address"]),
    ...(verifiedAt === undefined ? {} : { verifiedAt }),
    ...(createdAt === undefined ? {} : { createdAt }),
  };
}

function companyPersonOf(value: unknown): CompanyPerson {
  const row = recordOf(value, "company person");
  const role = optionalText(row["role"]);

  return {
    ...personOf(row),
    primary: row["is_primary"] === true,
    ...(role === undefined ? {} : { role }),
  };
}

const dateOf = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().PlainDate.from(value.slice(0, 10))
    : undefined;

function representationOf(row: Record<string, unknown>): Representation {
  const validFrom = dateOf(row["validFrom"]);
  const validUntil = dateOf(row["validUntil"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    personId: textOf(row["personId"]),
    role: enumOrThrow(row["role"], REPRESENTATIVE_ROLES, "representative role"),
    authority: enumOrThrow(
      row["authority"],
      REPRESENTATIVE_AUTHORITIES,
      "representative authority",
    ),
    ...(validFrom === undefined ? {} : { validFrom }),
    ...(validUntil === undefined ? {} : { validUntil }),
  };
}

function representativeOf(value: unknown): Representative {
  const row = recordOf(value, "representative");
  const email = optionalText(row["email"]);
  const phone = optionalText(row["phone"]);
  const createdAt = optionalInstant(row["createdAt"]);

  return {
    ...representationOf(row),
    name: textOf(row["name"]),
    active: row["active"] === true,
    ...(email === undefined ? {} : { email }),
    ...(phone === undefined ? {} : { phone }),
    ...(createdAt === undefined ? {} : { createdAt }),
  };
}

function representedOf(value: unknown): RepresentedRecord {
  const row = recordOf(value, "represented record");

  return {
    ...representationOf(row),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
  };
}

/**
 * The attrs of a write: the keys the input sets, `null` included, and its
 * fields.
 */
function attrsOf(input: CompanyInput | PersonInput): Record<string, unknown> {
  const { id: _id, fields, creditLimit, ...rest } = input;

  return {
    ...rest,
    ...(creditLimit === undefined
      ? {}
      : {
          creditLimit: creditLimit === null ? null : amountText(creditLimit),
          creditCurrency: creditLimit?.currency ?? null,
        }),
    ...fields,
  };
}

function partyOf(value: unknown): Party {
  const row = recordOf(value, "party");

  return row["type"] === "person"
    ? { type: "person", person: personOf(row["party"]) }
    : { type: "company", company: companyOf(row["party"]) };
}

function pageFrom<T extends { readonly id: string; readonly name: string }>(
  rows: readonly T[],
  limit: number | undefined,
): PartyPage<T> {
  const last = rows.at(-1);

  return rows.length === (limit ?? 50) && last !== undefined
    ? { items: rows, next: { name: last.name, id: last.id } }
    : { items: rows };
}

/**
 * The parties block: companies and people an organization works with. Register
 * them in `config.subjects` with `partiesSubjects()` so comments, tags, files,
 * pipelines and deals can point at them.
 */
export function createContacts<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ContactsOptions<S>): Contacts<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);

  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "company fields");

  const company = (result: AsyncResult<Company>): AsyncResult<Company<F>> =>
    result.andThen((row) => readFields(fields, row));

  const party = (result: AsyncResult<Party>): AsyncResult<Party<F>> =>
    result.andThen((found) =>
      found.type === "person"
        ? AsyncResult.ok<Party<F>>(found)
        : readFields(fields, found.company).map((read): Party<F> => ({
            type: "company",
            company: read,
          })),
    );

  const list = <T extends { readonly id: string; readonly name: string }>(
    fn: string,
    organizationId: string,
    listOptions: PartyListOptions,
    map: (value: unknown) => T,
  ) => {
    const { limit, cursor } = pageOf(listOptions);

    return call(
      fn,
      {
        tenant: organizationId,
        search: listOptions.search ?? null,
        lifecycle: listOptions.lifecycle ?? null,
        owner: listOptions.ownerId ?? null,
        after_name: cursor?.name ?? null,
        after_id: cursor?.id ?? null,
        page_size: limit ?? null,
        role: listOptions.role ?? null,
        supplier_status: listOptions.supplierStatus ?? null,
      },
      (value) => pageFrom(recordsOf(value, fn).map(map), limit),
    );
  };

  const client: Contacts<F> = {
    saveCompany: (organizationId, input) =>
      writeFields(fields, input.fields, (checked) =>
        company(
          call(
            "save_company",
            {
              tenant: organizationId,
              company: input.id ?? null,
              attrs: attrsOf({
                ...input,
                ...(checked === undefined ? {} : { fields: checked }),
              }),
            },
            companyOf,
          ),
        ),
      ),
    savePerson: (organizationId, input) =>
      call(
        "save_person",
        {
          tenant: organizationId,
          person: input.id ?? null,
          attrs: attrsOf(input),
        },
        personOf,
      ),
    archiveCompany: (id, archived = true) =>
      call("archive_company", { id, archived }, (value) => value === true),
    archivePerson: (id, archived = true) =>
      call("archive_person", { id, archived }, (value) => value === true),
    linkPerson: (companyId, personId, link = {}) =>
      call(
        "set_company_person",
        {
          company: companyId,
          person: personId,
          role: link.role ?? null,
          is_primary: link.primary ?? false,
        },
        (value) => value === true,
      ),
    unlinkPerson: (companyId, personId) =>
      call(
        "remove_company_person",
        { company: companyId, person: personId },
        (value) => value === true,
      ),
    mergeCompanies: (keep, drop) =>
      company(call("merge_companies", { keep, drop }, companyOf)),
    mergePeople: (keep, drop) => call("merge_people", { keep, drop }, personOf),
    listCompanies: (organizationId, listOptions = {}) =>
      list("list_companies", organizationId, listOptions, companyOf).andThen(
        (page) =>
          readAllFields(fields, page.items).map((items) => ({
            ...page,
            items,
          })),
      ),
    listPeople: (organizationId, listOptions = {}) =>
      list("list_people", organizationId, listOptions, personOf),
    identities: (personId) =>
      call("list_person_identities", { person: personId }, (value) =>
        recordsOf(value, "list_person_identities").map(identityOf),
      ),
    addIdentity: (personId, identity) =>
      call(
        "add_person_identity",
        {
          person: personId,
          channel: identity.channel,
          address: identity.address,
          verified: identity.verified ?? false,
        },
        identityOf,
      ),
    removeIdentity: (identityId) =>
      call(
        "remove_person_identity",
        { identity: identityId },
        (value) => value === true,
      ),
    findByIdentity: (organizationId, channel, address) =>
      call(
        "find_person_by_identity",
        { tenant: organizationId, channel, address },
        (value) => (value === null ? undefined : personOf(value)),
      ),
    setRoles: (partyId, roles) =>
      party(call("set_party_roles", { party: partyId, roles }, partyOf)),
    setSupplierStatus: (partyId, status, reason) =>
      party(
        call(
          "set_supplier_status",
          { party: partyId, status, reason: reason ?? null },
          partyOf,
        ),
      ),
    supplierStatusFromQualifications: (companyId) =>
      call(
        "supplier_status_from_qualifications",
        { party: companyId },
        (value) => enumOrThrow(value, SUPPLIER_STATUSES, "supplier status"),
      ),
    peopleOf: (companyId) =>
      call("company_people_of", { company: companyId }, (value) =>
        recordsOf(value, "company_people_of").map(companyPersonOf),
      ),
    representativesOf: (subjectType, subjectId) =>
      call(
        "list_representatives",
        { subject_type: subjectType, subject_id: subjectId },
        (value) =>
          recordsOf(value, "list_representatives").map(representativeOf),
      ),
    representedByMe: (organizationId) =>
      call("represented_by_me", { tenant: organizationId }, (value) =>
        recordsOf(value, "represented_by_me").map(representedOf),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "contacts",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
