import type {
  BlockFields,
  FieldsOf,
  RowFields,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { CursorPageOptions } from "../shared.ts";

import {
  blockFields,
  readAllFields,
  readFields,
  writeFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  blockCall,
  isRecord,
  optionalText,
  pageOf,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

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
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: Readonly<Record<string, unknown>>;
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
  /** The user this person signs in as, for a portal. */
  readonly userId?: string;
}

/** A person at a company. */
export interface CompanyPerson extends Person {
  readonly role?: string;
  /** Whether this is the company's primary contact. */
  readonly primary: boolean;
}

/**
 * The fields of a write. Left out keeps the stored value; `null` clears it (a
 * name and a lifecycle can't be cleared).
 */
export interface CompanyInput<F extends object = Record<never, never>> {
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

export interface PersonInput {
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
  /** Merges `drop` into `keep`. Needs `parties.manage`. */
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
  /** A company's people with their role, primary contact first. */
  peopleOf(companyId: string): AsyncResult<CompanyPerson[]>;
  /** Links an inbox contact to a person. Needs the inbox module. */
  linkInboxContact(personId: string, contactId: string): AsyncResult<boolean>;
  unlinkInboxContact(contactId: string): AsyncResult<boolean>;
  /**
   * The person an inbox contact is: its link, else the person with its email
   * (then linked), else with `create` a new lead from the contact.
   */
  personForInboxContact(
    contactId: string,
    options?: { readonly create?: boolean },
  ): AsyncResult<Person | undefined>;
}

export interface ContactsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> {
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

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    name: textOf(row["name"]),
    lifecycle: textOf(row["lifecycle"]),
    archived: row["archived_at"] !== null && row["archived_at"] !== undefined,
    fields: isRecord(fields) ? fields : fieldsOf(row, known),
    ...(ownerId === undefined ? {} : { ownerId }),
    ...(mergedInto === undefined ? {} : { mergedInto }),
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

  return {
    ...base(row, PERSON_COLUMNS),
    ...(email === undefined ? {} : { email }),
    ...(phone === undefined ? {} : { phone }),
    ...(title === undefined ? {} : { title }),
    ...(userId === undefined ? {} : { userId }),
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

/**
 * The attrs of a write: the keys the input sets, `null` included, and its
 * fields.
 */
function attrsOf(input: CompanyInput | PersonInput): Record<string, unknown> {
  const { id: _id, fields, ...rest } = input;

  return { ...rest, ...fields };
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
 * them in `config.records` with `partiesSubjects()` so comments, tags, files,
 * pipelines and deals can point at them.
 */
export function createContacts<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ContactsOptions<S>): Contacts<FieldsOf<S>> {
  type F = FieldsOf<S>;

  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "company fields");

  const company = (result: AsyncResult<Company>): AsyncResult<Company<F>> =>
    result.andThen((row) => readFields(fields, row));

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
    linkInboxContact: (personId, contactId) =>
      call(
        "link_inbox_contact",
        { person: personId, contact: contactId },
        (value) => value === true,
      ),
    unlinkInboxContact: (contactId) =>
      call(
        "unlink_inbox_contact",
        { contact: contactId },
        (value) => value === true,
      ),
    personForInboxContact: (contactId, find = {}) =>
      call(
        "person_for_inbox_contact",
        { contact: contactId, create: find.create ?? false },
        (value) => (value === null ? undefined : personOf(value)),
      ),
    peopleOf: (companyId) =>
      call("company_people_of", { company: companyId }, (value) =>
        recordsOf(value, "company_people_of").map(companyPersonOf),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "contacts",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
