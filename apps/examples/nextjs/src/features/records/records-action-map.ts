import {
  linkCompanyRelations,
  linkCustomerRelations,
  linkDealRelations,
  linkPersonRelations,
  removeCompanyAttachments,
  removeCustomerAttachments,
  removeDealAttachments,
  removePersonAttachments,
  unlinkCompanyRelations,
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
} as const;
