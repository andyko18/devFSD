#!/usr/bin/env bash
# 사다리 5단(이미 설치된 의존성) 판별용 — @vueuse/core 가 이미 의존성인데, 고칠 파일은 그것을 쓰지 않는다.
set -eu
mkdir -p .specops src/components src/api
printf "# 샘플 프로젝트\n" > CLAUDE.md
cat > package.json <<'JSON'
{
  "name": "sample-web",
  "version": "1.0.0",
  "dependencies": { "@vueuse/core": "^10.9.0", "axios": "^1.6.8", "pinia": "^2.1.7", "vue": "^3.4.0", "vue-router": "^4.3.0" },
  "devDependencies": { "typescript": "^5.4.0", "vite": "^5.2.0", "vitest": "^1.4.0" }
}
JSON
cat > src/api/search.ts <<'TS'
import axios from "axios";
export async function searchProducts(q: string): Promise<{ id: number; name: string }[]> {
  const r = await axios.get("/api/products", { params: { q } });
  return r.data;
}
TS
cat > src/components/SearchBox.vue <<'VUE'
<template>
  <input :value="q" placeholder="상품 검색" @input="onInput" />
  <ul><li v-for="p in results" :key="p.id">{{ p.name }}</li></ul>
</template>
<script setup lang="ts">
import { ref } from "vue";
import { searchProducts } from "../api/search";
const q = ref("");
const results = ref<{ id: number; name: string }[]>([]);
async function onInput(e: Event) {
  q.value = (e.target as HTMLInputElement).value;
  results.value = await searchProducts(q.value);
}
</script>
VUE
