import type { RecordBinding } from "../record-bindings.ts";
import type { SignatureRequest, Signatures } from "./signatures.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/** The signature requests made on a record, newest first. */
export const signaturesBinding: RecordBinding<
  Signatures,
  readonly SignatureRequest[]
> = defineRecordBinding({
  permissions: { read: "read" },
  module: "signatures",
  load: (client: Signatures, subject) =>
    client.list({ subjectType: subject.type, subjectId: subject.id }),
  timeline: (requests) =>
    requests.map((request) => ({
      id: request.id,
      kind: "signature_request",
      at: request.createdAt,
      ...(request.requestedBy === undefined
        ? {}
        : { actor: request.requestedBy }),
      row: request,
    })),
  events: ["signature_request.*"],
});
