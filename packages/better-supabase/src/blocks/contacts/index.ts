export {
  type Company,
  type CompanyInput,
  type CompanyPerson,
  createContacts,
  type Contacts,
  type ContactsOptions,
  type PartyCursor,
  type PartyListOptions,
  type PartyPage,
  type Person,
  type PersonInput,
} from "./contacts.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
  type BlockHooks,
  type BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
  type BlockTransport,
  type RpcClient,
} from "../../core/block-transport.ts";

export { contactsBlock } from "./manifest.ts";

export { contactsEvents } from "./events.ts";

export type { ContactsEvents } from "./events.ts";

export {
  companyInputSchema,
  partyListFilterSchema,
  personInputSchema,
} from "./schemas.ts";
