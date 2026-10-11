---
"better-supabase": minor
---

New `better-supabase/overlay` subpath for OpenAPI Overlay 1.0, 1.1 and 1.2 documents. `applyOverlay` and `applyOverlays` apply them to any JSON document, with RFC 9535 JSONPath targets, a diagnostic for each target that matches nothing, and the 1.2 reusable actions (`expandReusableActions`). `defineOverlay` types an overlay in code, and `overlayFromDiff` writes the overlay that turns one document into another. JSONPath comes from the optional `jsonpath-rfc9535` peer, loaded on first use, or from an engine you pass. The subpath imports no Node built-in, so it runs on every WinterTC runtime.
