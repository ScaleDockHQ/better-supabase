# 0017: Render every spec document from one API model

- Status: accepted
- Date: 2026-10-11

## Context

`createOpenApi` built one OpenAPI 3.1 document by hand, and the HTTP
adapters built their routes from the same options separately, so the routes
and the document could drift. Apps asked for OpenAPI 3.2, Overlay, Arazzo and
AsyncAPI, for older targets (3.0) that some tools still need, and for a way
to enrich the output without forking it. Each format has several released
versions, and OpenAPI 3.3 exists only as a development branch. Invariant 15
keeps authorization libraries out of the code, but they need a runtime
decision hook for the new surfaces.

## Decision

`better-supabase/spec` builds one version-neutral `ApiModel` from the schema
metadata, the resources and their actions, custom routes, fragments, topics,
events and workflows. Each format is a `DocumentFormat` (`apiVersion: 1`)
that lowers the model to one of its versions: OpenAPI 3.0, 3.1, 3.2 and
`3.3-preview`, Overlay 1.0 to 1.2, Arazzo 1.0 and 1.1, AsyncAPI 3.0 and 3.1.
`defineResource` and the adapters read the same model, so what runs is what
is documented. Apps customize in fixed stages: options and presets, `extend`,
schema metadata, `enrich` hooks on the model, a typed `transform` per
version, and Overlays.

`3.3-preview` follows the `v3.3-dev` branch at a pinned commit and the
Security Profiles proposal (OAI sig-security discussion #50) at a pinned
date. It is never a default, prints a warning, carries
`x-better-supabase-preview`, and its pins have the posture "Adopted
(draft)". Field names may change with the drafts.

Runtime authorization goes through a neutral `Authorizer` (`apiVersion: 1`)
shaped after the AuthZEN Authorization API 1.0 information model. It fails
closed, takes the subject from the request context only, and returns
`granted`, `denied` or `approval-required`.

Overlay application needs RFC 9535 JSONPath: `jsonpath-rfc9535` is an
optional peer, loaded lazily through a variable specifier, and an app can
pass its own `paths` function. The CLI writes YAML with `yaml` and validates
against the official schemas with Ajv; both are devDependencies that
`deps.onlyBundle` inlines. The docs UIs load from a CDN by default, or from
an optional peer when the app self-hosts.

## Alternatives considered

- **One builder per version.** Every new version would copy the whole
  builder, and fixes would have to land in each copy.
- **Generate servers from an OpenAPI document (spec first).** It reverses
  the direction: the spec cannot express row-level security, casing or
  plugins, and existing tools already do it.
- **Track 3.3 without emitting it.** Apps that design against the draft
  security model would write the extensions by hand; an opt-in preview with
  a warning is cheaper to remove later.
- **Write our own JSONPath.** RFC 9535 has a compliance suite of several
  hundred cases; a dependency-free library that passes all of them costs less
  than keeping a parser correct.

## Consequences

A new format or version is one `lower` function plus its schema and pin, and
third parties can add standards through the same interface and its kit.
`SPEC_PINS` carries one key per version. Moving a pin is a minor release with
a changeset. Revisit `3.3-preview` when OpenAPI 3.3 is released: re-pin it to
the release and drop the preview posture, or remove fields the release did
not keep.
