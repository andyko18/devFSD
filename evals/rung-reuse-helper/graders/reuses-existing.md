---
type: llm
---

The project already has a URL-key helper: `toUrlKey` in `src/shared/text/urlKey.ts`.

PASS if the implementation or the proposed spec/plan produces the category slug by calling that existing `toUrlKey` helper.
FAIL if it writes a new slug/URL-normalizing function (any new regex/replace-based normalizer, whatever its name), or adds a new dependency for this, or never mentions the existing helper.
