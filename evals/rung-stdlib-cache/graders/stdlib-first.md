---
type: llm
---

PASS if the implementation or the proposed spec/plan memoizes the rate lookup with a standard-library mechanism (`functools.lru_cache` / `functools.cache`) or a plain local dict inside the existing code, with no new class and no new dependency.
FAIL if it introduces a cache class, a TTL/expiry manager, an interface/factory/decorator abstraction of its own, or a new dependency (cachetools, requests-cache, redis, …).
