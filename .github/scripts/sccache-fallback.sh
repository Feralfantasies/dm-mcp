#!/usr/bin/env bash
# sccache-fallback.sh — run a cargo command with failover from the shared
# sccache server.
#
# The firethorn runner pods inject RUSTC_WRAPPER=sccache, pointing at an
# org-wide remote sccache server. That server is flaky: a client can time
# out waiting for the server to accept a new session even when
# `sccache --show-stats` succeeds. Observed 2026-11-07 (dm-mcp PR #59): the
# pre-build probe passed at 22:22:09 and `cargo clippy` died two seconds
# later with:
#   sccache: error: Timed out waiting for server startup.
#            Maybe the remote service is unreachable?
# SCCACHE_IGNORE_SERVER_IO_ERROR does not cover that startup handshake, and
# sccache's startup wait is not configurable, so a pre-build probe alone can
# never guarantee a build.
#
# This script makes the failure recoverable: run the command, and if it
# fails with an sccache error (i.e. the compiler driver itself failed, not
# our code), disable RUSTC_WRAPPER for the rest of the job and retry the
# same command once, uncached. A second failure is real and propagates.
#
# Usage: bash .github/scripts/sccache-fallback.sh cargo <args...>
set -o pipefail

log="$(mktemp)"
"$@" 2>&1 | tee "$log"
status=$?

if [ "$status" -ne 0 ] && [ -n "${RUSTC_WRAPPER:-}" ] && grep -q 'sccache: error' "$log"; then
  echo "::warning::sccache failed mid-job (exit $status) — retrying without the compile cache"
  tail -n 5 "$log"
  echo "RUSTC_WRAPPER=" >> "$GITHUB_ENV"
  RUSTC_WRAPPER= "$@"
  status=$?
fi

rm -f "$log"
exit "$status"
