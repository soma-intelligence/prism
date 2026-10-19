#!/bin/zsh
# Applies supabase/migrations to a throwaway Postgres 17 and runs
# supabase/tests/*.sql, without Docker or the Supabase CLI.
#
#   supabase/scripts/local-test/run.sh            # every test file
#   supabase/scripts/local-test/run.sh rls.sql    # one
#
# Needs Homebrew's postgresql@17 (initdb, pg_ctl, psql). The cluster lives in
# /tmp and listens on TCP only: a Unix socket under a long temporary path
# goes past macOS's limit and the server refuses to start.
set -euo pipefail
export LC_ALL=${LC_ALL:-en_US.UTF-8}  # postgres refuses to start under an unset locale

HERE=${0:A:h}
ROOT=${HERE:h:h}
PORT=${PORT:-54351}
DATA=$(mktemp -d /tmp/soma-app-pg.XXXXXX)
export PGOPTIONS="-c client_min_messages=warning"
PSQL=(psql -X -q -h 127.0.0.1 -p "$PORT" -U postgres -v ON_ERROR_STOP=1)

cleanup() { pg_ctl -D "$DATA" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$DATA"; }
trap cleanup EXIT

initdb -D "$DATA" -U postgres --auth=trust >/dev/null
pg_ctl -D "$DATA" -l "$DATA/log.txt" -o "-c unix_socket_directories='' -c listen_addresses=127.0.0.1 -p $PORT" -w start >/dev/null || { cat "$DATA/log.txt"; exit 1; }

run_suite() {
    local test=$1 db=$2
    createdb -h 127.0.0.1 -p "$PORT" -U postgres "$db"
    "${PSQL[@]}" -d "$db" -f "$HERE/shims.sql" >/dev/null
    "${PSQL[@]}" -d "$db" -f "$HERE/pgtap-lite.sql" >/dev/null
    for migration in "$ROOT"/migrations/*.sql; do
        # Hosted Supabase installs these; locally the shims stand in.
        sed -E '/^create extension if not exists (pg_cron|pg_net);/d' "$migration" | "${PSQL[@]}" -1 -d "$db" >/dev/null
    done
    "${PSQL[@]}" -At -d "$db" -f "$test"
}

result=0
tests=("${@:-}")
if [[ -z "${tests[1]}" ]]; then tests=("$ROOT"/tests/*.sql); else tests=("${tests[@]/#/$ROOT/tests/}"); fi
index=0
for test in "${tests[@]}"; do
    index=$((index + 1))
    echo "# ${test:t}"
    output=$(run_suite "$test" "t$index" 2>&1) || result=1
    echo "$output"
    if print -r -- "$output" | grep -qE '^not ok|^# Looks like you failed|ERROR'; then result=1; fi
done
exit $result
