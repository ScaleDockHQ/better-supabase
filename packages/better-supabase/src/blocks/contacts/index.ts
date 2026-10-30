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
  type PersonIdentity,
  type PersonIdentityInput,
  type PersonInput,
  type Representation,
  type Representative,
  type RepresentedRecord,
} from "./contacts.ts";

export {
  REPRESENTATIVE_AUTHORITIES,
  REPRESENTATIVE_ROLES,
  type RepresentativeAuthority,
  type RepresentativeRole,
} from "./representatives.ts";

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
