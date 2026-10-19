#!/bin/zsh
# Runs every supabase/functions/**/*_test.ts. With Deno installed it is plain
# `deno test`; without it, the tests run under Bun with a stand-in for
# Deno.test and jsr:@std/assert (Bun cannot resolve jsr: imports).
set -euo pipefail
HERE=${0:A:h}
FUNCTIONS=${HERE:h}/functions

if command -v deno >/dev/null; then
    cd "$FUNCTIONS" && exec deno test --allow-read --allow-env
fi

WORK=$(mktemp -d /tmp/soma-functions.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
cp -R "$FUNCTIONS"/. "$WORK"/
cat > "$WORK/_assert.ts" <<'TS'
import { deepStrictEqual } from "node:assert";
export function assert(c: unknown, msg?: string): asserts c { if (!c) throw new Error(msg ?? "assertion failed"); }
export function assertEquals(a: unknown, b: unknown, msg?: string) { deepStrictEqual(a, b, msg); }
TS
cat > "$WORK/_deno.ts" <<'TS'
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
const tests: { name: string; fn: () => unknown }[] = [];
(globalThis as any).Deno = {
  test(name: string, fn: () => unknown) { tests.push({ name, fn }); },
  readTextFileSync(u: URL | string) { return readFileSync(typeof u === "string" ? u : fileURLToPath(u), "utf8"); },
  env: { get: () => undefined },
};
export async function runAll(): Promise<number> {
  let failed = 0;
  for (const t of tests) {
    try { await t.fn(); console.log("ok", t.name); }
    catch (e) { failed++; console.log("FAIL", t.name, "\n  ", String((e as Error).message).slice(0, 800)); }
  }
  console.log(`${tests.length - failed} passed, ${failed} failed`);
  return failed;
}
TS
imports=""
for test in "$WORK"/**/*_test.ts; do
    depth=${${test#$WORK/}//[^\/]}
    sed -i '' "s|jsr:@std/assert@1|../_assert.ts|" "$test"
    imports+="await import(\"${test}\");"$'\n'
done
print -r -- "import { runAll } from \"./_deno.ts\";"$'\n'"$imports"'process.exit(await runAll() > 0 ? 1 : 0);' > "$WORK/_run.ts"
cd "$WORK" && bun run _run.ts
