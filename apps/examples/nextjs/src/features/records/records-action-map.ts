import {
  linkContractRelations,
  linkCompanyRelations,
  linkCustomerRelations,
  linkDealRelations,
  linkPersonRelations,
  removeCompanyAttachments,
  removeContractAttachments,
  removeCustomerAttachments,
  removeDealAttachments,
  removePersonAttachments,
  unlinkCompanyRelations,
  unlinkContractRelations,
  unlinkCustomerRelations,
  unlinkDealRelations,
  unlinkPersonRelations,
} from "./records-actions";

/** The Server Actions of the shared sections, by record type. */
export const recordActions = {
  customer: {
    link: linkCustomerRelations,
    unlink: unlinkCustomerRelations,
    removeAttachment: removeCustomerAttachments,
  },
  company: {
    link: linkCompanyRelations,
    unlink: unlinkCompanyRelations,
    removeAttachment: removeCompanyAttachments,
  },
  person: {
    link: linkPersonRelations,
    unlink: unlinkPersonRelations,
    removeAttachment: removePersonAttachments,
  },
  deal: {
    link: linkDealRelations,
    unlink: unlinkDealRelations,
    removeAttachment: removeDealAttachments,
  },
  contract: {
    link: linkContractRelations,
    unlink: unlinkContractRelations,
    removeAttachment: removeContractAttachments,
  },
} as const;
