import type { EntitySchema } from "../entity-schema.ts";
import type { MailSendDraft } from "./mail-sync.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `connect` takes. */
export interface MailAccountInput {
  readonly provider: string;
  readonly address: string;
  readonly credentialRef: Readonly<Record<string, unknown>>;
  readonly share?: "records" | "private";
}

/** What `connect` takes. The SQL checks the address and the ref's tenant. */
export const mailAccountInputSchema: EntitySchema<MailAccountInput> =
  entitySchema<MailAccountInput>({
    title: "MailAccountInput",
    fields: {
      provider: { kind: "string", minLength: 1, maxLength: 40 },
      address: { kind: "string", minLength: 3, maxLength: 320 },
      credentialRef: {
        kind: "json",
        description: "The member's OAuth grant: { provider, tenant, ... }.",
      },
      share: { kind: "enum", values: ["records", "private"], optional: true },
    },
  });

/** What `send` takes. */
export const mailDraftSchema: EntitySchema<MailSendDraft> =
  entitySchema<MailSendDraft>({
    title: "MailDraft",
    fields: {
      to: {
        kind: "json",
        array: true,
        description: "The recipients: { address, name? }.",
      },
      cc: { kind: "json", array: true, optional: true },
      bcc: { kind: "json", array: true, optional: true },
      subject: { kind: "string", maxLength: 998 },
      text: { kind: "string", optional: true },
      html: { kind: "string", optional: true },
      threadId: { kind: "uuid", optional: true },
    },
  });
