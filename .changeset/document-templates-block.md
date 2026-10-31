---
"better-supabase": minor
---

New `document-templates` block (`better-supabase/blocks/document-templates`): templates per legal entity and language for invoices, credit notes, quotes, orders, dunning letters, delivery notes and statements, with reusable text blocks and a snapshot that keeps an issued document stable.

- `saveTemplate`, `setTemplateActive`, `getTemplate` and `listTemplates` keep one template per document type, name, legal entity and language. A body that names an unknown variable or filter, or leaves a block open, fails with the hint `DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE`, `DOCUMENT_TEMPLATE_UNKNOWN_FILTER` or `DOCUMENT_TEMPLATE_SYNTAX`.
- `saveTextBlock` and `listTextBlocks` keep texts a template reads as `{{texts.key}}`.
- `resolveTemplate` picks the entity and language, the entity, the organization and language, then the organization, like `resolve_setting`.
- `render` returns the typed variables of a document with the chosen template and text blocks, in the buyer's language unless you pass one. `renderHtml` and `renderDocumentHtml` render to HTML in pure TypeScript with every value escaped.
- Issuing an invoice or credit note freezes its render in `rendered_documents`; `freeze` does the same for other documents, and `fresh: true` renders with today's templates.
- `contract` and `documentContract` publish the variable contract (version 1). Templates and text blocks are import targets (`document_template`, `document_text_block`).
- The permission keys are `document_templates.read` and `document_templates.manage`; members get `read`.

Add `"document-templates": {}` to `blocks`, run `better-supabase add document-templates` and generate a migration. The block needs `legal-entities`.
