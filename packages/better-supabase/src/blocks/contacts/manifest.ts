import type { BlockOf } from "../define-block.ts";
import type { ContactsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createContacts } from "./contacts.ts";
import { contactsEvents } from "./events.ts";
import { contactsSqlOptions } from "./options.ts";
import {
  companyInputSchema,
  partyListFilterSchema,
  personInputSchema,
} from "./schemas.ts";

/** The `contacts` block's manifest (ADR 0029). */
export const contactsBlock: BlockOf<
  "contacts",
  typeof createContacts,
  ContactsEvents
> = defineBlock({
  name: "contacts",
  sql: ["contacts"],
  options: { contacts: contactsSqlOptions },
  events: contactsEvents,
  create: createContacts,
  category: "crm",
  importTarget: [
    "payment_term",
    "document_delivery_preference",
    "party",
    "party_contact",
    "contact_method",
    "party_location",
    "party_bank_account",
  ],
  entities: {
    company: { mutability: "editable", emits: { create: true, update: true } },
    person: { mutability: "editable", emits: { create: true, update: true } },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Companies and people an organization works with: lifecycle stages, owners, party roles (customer, supplier and so on), payment terms with early-payment discounts and credit restrictions, credit limits with a soft or hard block, a language, delivery preferences per document type and a supplier status, who works where with a role and a primary contact, each person's addresses on channels (the inbox's contacts), domain and email dedupe, merges and keyset-paged search.",
  recipes: ["contact-detail"],
  schemas: {
    company: { input: companyInputSchema, listFilter: partyListFilterSchema },
    person: { input: personInputSchema, listFilter: partyListFilterSchema },
  },
});
