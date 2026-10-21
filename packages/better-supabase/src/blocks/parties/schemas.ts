import type { EntitySchema } from "../entity-schema.ts";
import type { CompanyInput, PartyListOptions, PersonInput } from "./parties.ts";

import { entitySchema } from "../entity-schema.ts";

const NAME = {
  kind: "string",
  optional: true,
  minLength: 1,
  maxLength: 300,
  description: "Required when `id` is left out.",
} as const;

/** What `saveCompany` takes, with the bounds the SQL checks. */
export const companyInputSchema: EntitySchema<CompanyInput> =
  entitySchema<CompanyInput>({
    title: "CompanyInput",
    fields: {
      id: { kind: "uuid", optional: true },
      name: NAME,
      domain: { kind: "string", optional: true, nullable: true },
      website: { kind: "string", optional: true, nullable: true },
      vatId: { kind: "string", optional: true, nullable: true },
      lifecycle: { kind: "string", optional: true },
      ownerId: { kind: "uuid", optional: true, nullable: true },
      address: { kind: "json", optional: true, nullable: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set.",
      },
    },
  });

/** What `savePerson` takes, with the bounds the SQL checks. */
export const personInputSchema: EntitySchema<PersonInput> =
  entitySchema<PersonInput>({
    title: "PersonInput",
    fields: {
      id: { kind: "uuid", optional: true },
      name: NAME,
      email: { kind: "string", optional: true, nullable: true },
      phone: { kind: "string", optional: true, nullable: true },
      title: { kind: "string", optional: true, nullable: true },
      lifecycle: { kind: "string", optional: true },
      ownerId: { kind: "uuid", optional: true, nullable: true },
      userId: { kind: "uuid", optional: true, nullable: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set.",
      },
    },
  });

/** The options `listCompanies` and `listPeople` take. */
export const partyListFilterSchema: EntitySchema<PartyListOptions> =
  entitySchema<PartyListOptions>({
    title: "PartyListOptions",
    fields: {
      search: { kind: "string", optional: true },
      lifecycle: { kind: "string", optional: true },
      ownerId: { kind: "uuid", optional: true },
      limit: { kind: "integer", optional: true, minimum: 1 },
      cursor: {
        kind: "json",
        optional: true,
        description: "The last row's `{ name, id }`.",
      },
    },
  });
