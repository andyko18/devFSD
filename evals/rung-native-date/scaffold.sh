#!/usr/bin/env bash
# 사다리 4단(플랫폼 기본 기능) 판별용 — 날짜 라이브러리가 없는 React 프로젝트의 회원가입 폼
set -eu
mkdir -p .specops src/components
printf "# 샘플 프로젝트\n" > CLAUDE.md
cat > package.json <<'JSON'
{
  "name": "sample-signup",
  "version": "1.0.0",
  "dependencies": { "react": "^18.2.0", "react-dom": "^18.2.0" },
  "devDependencies": { "typescript": "^5.4.0", "vite": "^5.2.0" }
}
JSON
cat > src/components/SignupForm.tsx <<'TSX'
import { useState } from "react";

export function SignupForm({ onSubmit }: { onSubmit: (v: { email: string; name: string }) => void }) {
  const [email, setEmail] = useState("");
  const [name, setName] = useState("");
  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit({ email, name }); }}>
      <label>이메일 <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} /></label>
      <label>이름 <input type="text" required value={name} onChange={(e) => setName(e.target.value)} /></label>
      <button type="submit">가입</button>
    </form>
  );
}
TSX
