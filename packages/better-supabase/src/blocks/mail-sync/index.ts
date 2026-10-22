export {
  createMailSync,
  messageArg,
  type MailAccount,
  type MailMessage,
  type MailSendDraft,
  type MailSubject,
  type MailSync,
  type MailSyncOptions,
  type MailSyncReport,
  type MailTemplateStats,
  type MailThread,
  type MailThreadDetail,
} from "./mail-sync.ts";

export {
  buildMime,
  gmailMail,
  gmailMessage,
  mailProviderOf,
  newMessageId,
  outlookMail,
  outlookMessage,
  parseAddresses,
  type HttpMailOptions,
  type MailAddress,
  type MailDraft,
  type MailListInput,
  type MailPage,
  type MailProvider,
  type MailProviderMessage,
  type MailReplyTarget,
  type MailSendInput,
  type MailSent,
} from "./providers.ts";

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

export { mailSyncBlock } from "./manifest.ts";

export { mailSyncSqlOptions, type MailSyncSqlOptions } from "./options.ts";

export {
  mailAccountInputSchema,
  mailDraftSchema,
  type MailAccountInput,
} from "./schemas.ts";

export { mailSyncEvents } from "./events.ts";

export type { MailSyncEvents } from "./events.ts";
