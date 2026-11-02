# 0191: SMART App Launch and CDS Hooks helpers live in `better-supabase/fhir`

- Status: accepted
- Date: 2026-11-01

## Context

The care blocks export FHIR resources, and EHRs reach an app through SMART launches and ask for decision support through CDS Hooks.

## Decision

`better-supabase/fhir` gains `createSmartLaunch` with a versioned `SmartLaunchStore` port (`apiVersion: 1`), and `createCdsHooksServer` with a versioned `CdsService` port plus `cdsCardOfAlert`. Both use `fetch` and WebCrypto only and bundle no SDK. The pins are `smartAppLaunch` and `cdsHooks`.

## Alternatives considered

A SMART client package (rejected: another peer for roughly 150 lines). Storing launch state in a table (rejected: the store port lets an app use a cookie or its cache).

## Consequences

Backend services authorization and CDS request JWT verification stay with the app; the handler exposes `authorize`.
