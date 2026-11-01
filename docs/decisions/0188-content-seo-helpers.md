# 0188: Content writes sitemaps, robots.txt and JSON-LD as pure functions

- Status: accepted
- Date: 2026-11-01

## Context

Published entries need search engine output, and the URL scheme belongs to the app.

## Decision

`better-supabase/blocks/content` gains `sitemapXml`, `sitemapChunks`, `sitemapIndexXml`, `robotsTxt`, `articleJsonLd`, `breadcrumbJsonLd` and `jsonLdScript`. Pins are `sitemaps`, `rfc9309` and `jsonLd`.

## Alternatives considered

A Next.js metadata route (rejected: the block is router neutral).

## Consequences

No image or video sitemaps, and no FAQ or product structured data.
