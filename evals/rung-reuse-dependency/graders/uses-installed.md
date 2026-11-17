---
type: llm
---

The project already depends on `@vueuse/core`, which provides debounce utilities (`useDebounceFn`, `watchDebounced`, `refDebounced`, `useDebounce`).

PASS if the implementation or the proposed spec/plan debounces the search using one of the debounce utilities from the already-installed `@vueuse/core`.
FAIL if it hand-writes the debounce (a `setTimeout`/`clearTimeout` timer, or its own `debounce` helper), or adds a new dependency (such as lodash, lodash.debounce, lodash-es).
