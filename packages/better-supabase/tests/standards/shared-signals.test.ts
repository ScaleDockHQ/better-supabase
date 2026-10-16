import { describe, expect, it } from "vitest";

import {
  CAEP_EVENTS,
  createSsfReceiver,
  createSsfTransmitter,
  mintSet,
  RISC_EVENTS,
  SSF_EVENTS,
  SSF_POLL,
  SSF_PUSH,
} from "../../src/blocks/shared-signals/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { signingKey, store } from "../blocks/shared-signals/fixtures.ts";

const ISSUER = "https://tx.example";
const decode = (part: string): Record<string, unknown> =>
  JSON.parse(Buffer.from(part, "base64url").toString());

async function transmitter() {
  const t = store();
  const { signer, jwks } = await signingKey();
  const tx = createSsfTransmitter({
    transport: t,
    issuer: ISSUER,
    jwksUri: `${ISSUER}/jwks`,
    signer,
    authorize: () => ({ receiver: "rx" }),
  });
  return { t, jwks, tx };
}

describe(`Security Event Tokens (RFC 8417, ${SPEC_PINS.rfc8417})`, () => {
  it("mints a SET with typ secevent+jwt, iss, iat, jti, aud and one event", async () => {
    const { signer } = await signingKey();
    const { token } = await mintSet(signer, {
      issuer: ISSUER,
      audience: "rx",
      subject: { format: "opaque", id: "u1" },
      event: { type: CAEP_EVENTS.sessionRevoked, claims: {} },
    }).orThrow();
    const [header, payload] = token.split(".").slice(0, 2).map(decode);
    // §2.3: explicit typing with the secevent+jwt media type, without the application/ prefix.
    expect(header!["typ"]).toBe("secevent+jwt");
    expect(Object.keys(payload!).sort()).toEqual(
      ["aud", "events", "iat", "iss", "jti", "sub_id"].sort(),
    );
    // §2.2: events is a JSON object of event type URI to event payload.
    expect(payload!["events"]).toEqual({ [CAEP_EVENTS.sessionRevoked]: {} });
  });
});

describe(`Push delivery (RFC 8935, ${SPEC_PINS.rfc8935})`, () => {
  it("answers 202 to a valid SET and 400 with an err code from §2.4 otherwise", async () => {
    const { signer, jwks } = await signingKey();
    const push = createSsfReceiver({
      transport: store(),
      issuer: ISSUER,
      audience: "rx",
      jwks,
    }).pushHandler();
    const send = (body: string, type = "application/secevent+jwt") =>
      push(
        new Request("https://rx.example/ssf", {
          method: "POST",
          headers: { "content-type": type },
          body,
        }),
      );
    const { token } = await mintSet(signer, {
      issuer: ISSUER,
      audience: "rx",
      subject: { format: "opaque", id: "u1" },
      event: { type: RISC_EVENTS.accountDisabled, claims: {} },
    }).orThrow();
    expect((await send(token)).status).toBe(202);
    const wrongType = await send(token, "application/jwt");
    expect(wrongType.status).toBe(400);
    const body = await wrongType.json();
    expect(Object.keys(body).sort()).toEqual(["description", "err"]);
    expect([
      "invalid_request",
      "invalid_key",
      "invalid_issuer",
      "invalid_audience",
      "authentication_failed",
      "access_denied",
    ]).toContain(body.err);
  });
});

describe(`Poll delivery (RFC 8936, ${SPEC_PINS.rfc8936})`, () => {
  it("returns sets keyed by jti and moreAvailable, and drops acknowledged SETs", async () => {
    const { tx, t } = await transmitter();
    const stream = await tx
      .createStream({
        receiver: { receiver: "rx" },
        method: "poll",
        eventsRequested: [CAEP_EVENTS.credentialChange],
      })
      .orThrow();
    await tx
      .emit({
        subject: { format: "opaque", id: "u1" },
        event: { type: CAEP_EVENTS.credentialChange, claims: {} },
      })
      .orThrow();
    const handle = tx.handler();
    const poll = async (body: unknown) =>
      (
        await handle(
          new Request(`${ISSUER}/ssf/poll/${stream.id}`, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify(body),
          }),
        )
      ).json();
    const first = await poll({ maxEvents: 10, returnImmediately: true });
    expect(Object.keys(first).sort()).toEqual(["moreAvailable", "sets"]);
    const [jti] = Object.keys(first.sets);
    expect(typeof first.sets[jti!]).toBe("string");
    await poll({ maxEvents: 0, ack: [jti] });
    expect(t.queued).toHaveLength(0);
  });
});

describe(`Shared Signals Framework (SSF ${SPEC_PINS.ssf})`, () => {
  it("publishes the §7.1 transmitter metadata with the delivery method URNs", async () => {
    const { tx } = await transmitter();
    const metadata = tx.metadata();
    expect(metadata).toMatchObject({
      spec_version: "1_0",
      issuer: ISSUER,
      jwks_uri: `${ISSUER}/jwks`,
      delivery_methods_supported: ["urn:ietf:rfc:8935", "urn:ietf:rfc:8936"],
    });
    expect([SSF_PUSH, SSF_POLL]).toEqual([
      "urn:ietf:rfc:8935",
      "urn:ietf:rfc:8936",
    ]);
    expect(SSF_EVENTS).toEqual({
      verification:
        "https://schemas.openid.net/secevent/ssf/event-type/verification",
      streamUpdated:
        "https://schemas.openid.net/secevent/ssf/event-type/stream-updated",
    });
  });
});

describe(`CAEP (${SPEC_PINS.caep}) and RISC (${SPEC_PINS.risc}) event types`, () => {
  it("names every CAEP 1.0 event type", () => {
    const names = Object.values(CAEP_EVENTS).map((uri) =>
      uri.replace("https://schemas.openid.net/secevent/caep/event-type/", ""),
    );
    expect(names.sort()).toEqual(
      [
        "assurance-level-change",
        "credential-change",
        "device-compliance-change",
        "risk-level-change",
        "session-established",
        "session-presented",
        "session-revoked",
        "token-claims-change",
      ].sort(),
    );
  });

  it("names every RISC 1.0 event type but the deprecated sessions-revoked", () => {
    const names = Object.values(RISC_EVENTS).map((uri) =>
      uri.replace("https://schemas.openid.net/secevent/risc/event-type/", ""),
    );
    expect(names.sort()).toEqual(
      [
        "account-credential-change-required",
        "account-disabled",
        "account-enabled",
        "account-purged",
        "credential-compromise",
        "identifier-changed",
        "identifier-recycled",
        "opt-in",
        "opt-out-cancelled",
        "opt-out-effective",
        "opt-out-initiated",
        "recovery-activated",
        "recovery-information-changed",
      ].sort(),
    );
  });
});
