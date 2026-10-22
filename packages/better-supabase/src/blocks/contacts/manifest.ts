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

/** The `parties` block's manifest (ADR 0029). */
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
  recipes: ["contact-detail"],
  schemas: {
    company: { input: companyInputSchema, listFilter: partyListFilterSchema },
    person: { input: personInputSchema, listFilter: partyListFilterSchema },
  },
});
