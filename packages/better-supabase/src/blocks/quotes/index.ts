export {
  type CatalogLineInput,
  createQuotes,
  type Line,
  type LineInput,
  type PublicQuote,
  type Quote,
  type QuoteAnswer,
  type QuoteDecision,
  type QuoteInput,
  type QuoteLine,
  type QuoteLineInput,
  type QuotePricing,
  type QuoteResponse,
  type Quotes,
  type QuoteTaxLine,
  type QuoteVersion,
  type QuoteVersionSummary,
  type QuotesOptions,
  type QuoteStatus,
  type RecordRef,
  type Totals,
} from "./quotes.ts";

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

export { quotesBlock } from "./manifest.ts";

export { quotesEvents } from "./events.ts";

export type { QuotesEvents } from "./events.ts";

export { QUOTE_TO_ORDER, QUOTES_AUTOMATIONS } from "./automations.ts";

export type {
  DocumentVariant,
  QuoteVariants,
  QuoteVariantSelection,
} from "../sales-variants.ts";
