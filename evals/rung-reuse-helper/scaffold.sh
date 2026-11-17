#!/usr/bin/env bash
# 사다리 2단(이 코드베이스에 이미 있나?) 판별용 — URL 키 유틸이 "slug" 라는 이름 없이 다른 기능 폴더 옆 공용 폴더에 있다.
# 고칠 파일(shop/category.ts)에서는 그 유틸이 보이지 않는다 — 찾아봐야 나온다.
set -eu
mkdir -p .specops src/shared/text src/features/blog src/features/shop
printf "# 샘플 프로젝트\n" > CLAUDE.md
cat > package.json <<'JSON'
{ "name": "sample-shop", "version": "1.0.0", "type": "module", "devDependencies": { "typescript": "^5.4.0" } }
JSON
cat > src/shared/text/urlKey.ts <<'TS'
/** 사람이 읽는 이름을 URL 경로 조각으로 바꾼다 (한글 유지). */
export function toUrlKey(input: string): string {
  return input.toLowerCase().trim().replace(/[^a-z0-9가-힣]+/g, "-").replace(/^-+|-+$/g, "");
}
TS
cat > src/shared/text/truncate.ts <<'TS'
export function truncate(input: string, max: number): string {
  return input.length <= max ? input : input.slice(0, max - 1) + "…";
}
TS
cat > src/features/blog/post.ts <<'TS'
import { toUrlKey } from "../../shared/text/urlKey";
export interface Post { id: number; title: string; path: string }
export function makePost(id: number, title: string): Post { return { id, title, path: "/blog/" + toUrlKey(title) }; }
TS
cat > src/features/shop/category.ts <<'TS'
export interface Category { id: number; name: string }
export const categories: Category[] = [{ id: 1, name: "생활 가전" }, { id: 2, name: "Home & Kitchen" }];
TS
cat > src/features/shop/product.ts <<'TS'
export interface Product { id: number; categoryId: number; name: string; price: number }
TS
