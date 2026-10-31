import type { Money } from "../../commerce/money.ts";

import { money, toDecimal } from "../../commerce/money.ts";
import { SPEC_PINS } from "../../core/spec-pins.ts";

/** One credit transfer of a SEPA file. */
export interface SepaCreditTransfer {
  /** The SEPA EndToEndId: at most 35 characters. */
  readonly endToEndId: string;
  /** What is paid, in euros. */
  readonly amount: Money;
  readonly creditorName: string;
  readonly creditorIban: string;
  readonly creditorBic?: string;
  /** The unstructured remittance information. */
  readonly remittance?: string;
}

/** What `sepaCreditTransferXml` writes into one `pain.001.001.09` file. */
export interface SepaCreditTransferFile {
  /** The SEPA MsgId: at most 35 characters, unique per file. */
  readonly messageId: string;
  /** When the file was made, as an instant or an ISO 8601 text. */
  readonly createdAt: Temporal.Instant | string;
  /**
   * The day the bank executes the transfers, as `Temporal.PlainDate` or
   * `YYYY-MM-DD`.
   */
  readonly executionOn: Temporal.PlainDate | string;
  /** The account holder who pays. */
  readonly debtorName: string;
  readonly debtorIban: string;
  readonly debtorBic?: string;
  /** The initiating party's name. Default: the debtor. */
  readonly initiatingPartyName?: string;
  readonly transfers: readonly SepaCreditTransfer[];
}

const IBAN = /^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/;
const BIC = /^[A-Z]{6}[A-Z0-9]{2}(?:[A-Z0-9]{3})?$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const DISALLOWED = /[^a-zA-Z0-9/\-?:().,'+ ]/g;
const COMBINING = /\p{M}/gu;
const SPACES = / {2,}/g;

const XML_ESCAPES: Readonly<Record<string, string>> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&apos;",
};

/** The text in the SEPA character set (the Latin subset), cut to `max`. */
function sepaText(value: string, max: number): string {
  return value
    .normalize("NFKD")
    .replaceAll(COMBINING, "")
    .replaceAll(DISALLOWED, " ")
    .replaceAll(SPACES, " ")
    .trim()
    .slice(0, max);
}

const escape = (value: string): string =>
  value.replaceAll(/[&<>"']/g, (char) => XML_ESCAPES[char] ?? char);

const tag = (name: string, value: string): string =>
  `<${name}>${escape(value)}</${name}>`;

function required(value: string, max: number, field: string): string {
  const text = sepaText(value, max);

  if (text === "") {
    throw new RangeError(`${field} needs at least one SEPA character`);
  }

  return text;
}

function iban(value: string, field: string): string {
  const text = value.replaceAll(/\s/g, "").toUpperCase();

  if (!IBAN.test(text)) {
    throw new RangeError(`${field} is not an IBAN: "${value}"`);
  }

  return text;
}

function bicTag(value: string | undefined, field: string): string {
  if (value === undefined || value === "") {
    return "<FinInstnId><Othr><Id>NOTPROVIDED</Id></Othr></FinInstnId>";
  }

  const text = value.replaceAll(/\s/g, "").toUpperCase();

  if (!BIC.test(text)) {
    throw new RangeError(`${field} is not a BIC: "${value}"`);
  }

  return `<FinInstnId>${tag("BICFI", text)}</FinInstnId>`;
}

function identifier(value: string, field: string): string {
  const text = value.trim();

  if (text.length < 1 || text.length > 35 || text.includes(" ")) {
    throw new RangeError(
      `${field} is 1 to 35 characters without spaces: "${value}"`,
    );
  }

  return sepaText(text, 35);
}

/**
 * A SEPA credit transfer file as an ISO 20022 `pain.001.001.09` document: one
 * payment information block, charges shared (`SLEV`), the bank's `SEPA` service
 * level and the execution day. Names and remittance are cut to the SEPA
 * character set and length. Throws a `RangeError` for a currency other than
 * EUR, an amount of zero or less, a bad IBAN or BIC or an empty file.
 */
export function sepaCreditTransferXml(file: SepaCreditTransferFile): string {
  if (file.transfers.length === 0) {
    throw new RangeError("A SEPA file needs at least one transfer");
  }

  const executionOn = file.executionOn.toString();

  if (!DATE.test(executionOn)) {
    throw new RangeError(
      `executionOn is a date as YYYY-MM-DD: "${executionOn}"`,
    );
  }

  const messageId = identifier(file.messageId, "messageId");
  const created = file.createdAt.toString().slice(0, 19);
  const debtor = required(file.debtorName, 70, "debtorName");
  let total = 0n;
  const seen = new Set<string>();

  const transfers = file.transfers.map((transfer) => {
    if (transfer.amount.currency !== "EUR") {
      throw new RangeError("SEPA credit transfers are in EUR");
    }

    if (transfer.amount.amount <= 0n) {
      throw new RangeError("A transfer's amount is more than zero");
    }

    const endToEndId = identifier(transfer.endToEndId, "endToEndId");

    if (seen.has(endToEndId)) {
      throw new RangeError(`endToEndId repeats in the file: "${endToEndId}"`);
    }

    seen.add(endToEndId);
    total += transfer.amount.amount;

    const remittance =
      transfer.remittance === undefined
        ? ""
        : sepaText(transfer.remittance, 140);

    return `<CdtTrfTxInf><PmtId>${tag("EndToEndId", endToEndId)}</PmtId><Amt><InstdAmt Ccy="EUR">${toDecimal(transfer.amount)}</InstdAmt></Amt><CdtrAgt>${bicTag(transfer.creditorBic, "creditorBic")}</CdtrAgt><Cdtr>${tag("Nm", required(transfer.creditorName, 70, "creditorName"))}</Cdtr><CdtrAcct><Id>${tag("IBAN", iban(transfer.creditorIban, "creditorIban"))}</Id></CdtrAcct>${remittance === "" ? "" : `<RmtInf>${tag("Ustrd", remittance)}</RmtInf>`}</CdtTrfTxInf>`;
  });

  const count = String(transfers.length);
  const sum = toDecimal(money(total, "EUR"));
  const initiating = sepaText(file.initiatingPartyName ?? "", 70) || debtor;

  return `<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:${SPEC_PINS.pain001v09}" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><CstmrCdtTrfInitn><GrpHdr>${tag("MsgId", messageId)}${tag("CreDtTm", created)}${tag("NbOfTxs", count)}${tag("CtrlSum", sum)}<InitgPty>${tag("Nm", initiating)}</InitgPty></GrpHdr><PmtInf>${tag("PmtInfId", messageId)}<PmtMtd>TRF</PmtMtd><BtchBookg>true</BtchBookg>${tag("NbOfTxs", count)}${tag("CtrlSum", sum)}<PmtTpInf><SvcLvl><Cd>SEPA</Cd></SvcLvl></PmtTpInf><ReqdExctnDt><Dt>${executionOn}</Dt></ReqdExctnDt><Dbtr>${tag("Nm", debtor)}</Dbtr><DbtrAcct><Id>${tag("IBAN", iban(file.debtorIban, "debtorIban"))}</Id></DbtrAcct><DbtrAgt>${bicTag(file.debtorBic, "debtorBic")}</DbtrAgt><ChrgBr>SLEV</ChrgBr>${transfers.join("")}</PmtInf></CstmrCdtTrfInitn></Document>
`;
}
