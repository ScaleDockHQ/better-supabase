import {
  linkCaseRelations,
  removeCaseAttachments,
  unlinkCaseRelations,
  linkContractRelations,
  linkCompanyRelations,
  linkCustomerRelations,
  linkDealRelations,
  linkPersonRelations,
  linkShipmentRelations,
  linkWorkOrderRelations,
  removeCompanyAttachments,
  removeContractAttachments,
  removeCustomerAttachments,
  removeDealAttachments,
  removePersonAttachments,
  removeShipmentAttachments,
  removeWorkOrderAttachments,
  unlinkCompanyRelations,
  unlinkContractRelations,
  unlinkCustomerRelations,
  unlinkDealRelations,
  unlinkPersonRelations,
  unlinkShipmentRelations,
  unlinkWorkOrderRelations,
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
  // Service and logistics
  work_order: {
    link: linkWorkOrderRelations,
    unlink: unlinkWorkOrderRelations,
    removeAttachment: removeWorkOrderAttachments,
  },
  shipment: {
    link: linkShipmentRelations,
    unlink: unlinkShipmentRelations,
    removeAttachment: removeShipmentAttachments,
  },
  // Support
  case: {
    link: linkCaseRelations,
    unlink: unlinkCaseRelations,
    removeAttachment: removeCaseAttachments,
  },
} as const;
