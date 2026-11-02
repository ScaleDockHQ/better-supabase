# 0195: Maintenance ingests meter telemetry through a Fetch handler

- Status: accepted
- Date: 2026-11-01

## Context

Gateways push readings, and `recordReading` already rejects readings that go down.

## Decision

`better-supabase/blocks/maintenance` gains `parseTelemetryPoints`, `parseOtlpMetrics`, `ingestTelemetry` and `createTelemetryHandler`. The device-to-meter lookup is `meterFor` and `authorize` is required. Assets reach it through a meter's `assetId`. No new pin: the OTLP JSON shape is read through the existing OpenTelemetry pin.

## Alternatives considered

A SQL ingest function (rejected: it cannot be verified without the local stack). A queue backend (rejected: `ingestTelemetry` runs from any queue).

## Consequences

No downsampling or history table; the readings stay the meters' own.
