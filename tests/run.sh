#!/usr/bin/env bash
# unitcheck tests. Read-only; fixtures in a temp dir.
set -uo pipefail
cd "$(dirname "$0")/.."
UC="python3 unitcheck.py"
pass=0; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

assert() {   # <desc> <expect> -- <cmd...>
    local desc="$1" expect="$2"; shift 2; [[ "$1" == "--" ]] && shift
    local out; out="$("$@" 2>&1)"
    if grep -qF -- "$expect" <<<"$out"; then printf '  PASS  %s\n' "$desc"; pass=$((pass+1))
    else printf '  FAIL  %s\n        wanted: %s\n        got: %s\n' "$desc" "$expect" "$out"; fail=$((fail+1)); fi
}
refute() {   # <desc> <needle> -- <cmd...>
    local desc="$1" needle="$2"; shift 2; [[ "$1" == "--" ]] && shift
    local out; out="$("$@" 2>&1)"
    if grep -qF -- "$needle" <<<"$out"; then printf '  FAIL  %s (found %s)\n' "$desc" "$needle"; fail=$((fail+1))
    else printf '  PASS  %s\n' "$desc"; pass=$((pass+1)); fi
}
assert_exit() {  # <desc> <code> -- <cmd...>
    local desc="$1" want="$2"; shift 2; [[ "$1" == "--" ]] && shift
    "$@" >/dev/null 2>&1; local rc=$?
    if [[ "$rc" == "$want" ]]; then printf '  PASS  %s\n' "$desc"; pass=$((pass+1))
    else printf '  FAIL  %s (exit %s want %s)\n' "$desc" "$rc" "$want"; fail=$((fail+1)); fi
}

echo "== syntax =="
if python3 -c "import ast; ast.parse(open('unitcheck.py').read())"; then
    echo "  PASS  unitcheck.py parses"; pass=$((pass+1))
else echo "  FAIL  syntax"; fail=$((fail+1)); fi

echo "== a bare unit is weak =="
printf '[Unit]\nDescription=x\n[Service]\nExecStart=/usr/bin/myapp\n[Install]\nWantedBy=multi-user.target\n' > "$T/bare.service"
assert "no User flagged root"     "runs as root"        -- $UC "$T/bare.service" --no-color
assert "missing NoNewPrivileges"  "missing NoNewPrivileges" -- $UC "$T/bare.service" --no-color
assert "missing syscall filter"   "missing SystemCallFilter" -- $UC "$T/bare.service" --no-color
assert "bare scores weak"         "(weak)"              -- $UC "$T/bare.service" --no-color
assert_exit "bare unit exits non-zero" 1 -- $UC "$T/bare.service" --no-color

echo "== a fully hardened unit passes =="
cat > "$T/hard.service" <<'EOF'
[Unit]
Description=x
[Service]
ExecStart=/usr/bin/myapp
User=myapp
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
SystemCallFilter=@system-service
SystemCallArchitectures=native
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet=
[Install]
WantedBy=multi-user.target
EOF
assert "hardened scores 100"      "score: 100/100"      -- $UC "$T/hard.service" --no-color
assert "hardened band"            "(hardened)"          -- $UC "$T/hard.service" --no-color
assert_exit "hardened exits zero" 0 -- $UC "$T/hard.service" --no-color

echo "== dangerous explicit values =="
printf '[Service]\nExecStart=/x\nUser=svc\nNoNewPrivileges=no\nCapabilityBoundingSet=CAP_SYS_ADMIN\n' > "$T/danger.service"
assert "NoNewPrivileges=no flagged HIGH" "NoNewPrivileges=no" -- $UC "$T/danger.service" --no-color
assert "dangerous cap flagged"    "dangerous capability: CAP_SYS_ADMIN" -- $UC "$T/danger.service" --no-color

echo "== dynamic user model =="
sed '/User=myapp/c\DynamicUser=yes' "$T/hard.service" > "$T/dynamic.service"
refute "DynamicUser is not reported as root" "runs as root" -- $UC "$T/dynamic.service" --no-color
assert_exit "hardened DynamicUser unit passes" 0 -- $UC "$T/dynamic.service" --no-color

echo "== --min-score gate =="
# hardened unit but with a strict threshold that it still clears
assert_exit "hardened clears min-score 90" 0 -- $UC "$T/hard.service" --min-score 90 --no-color

echo
echo "== $pass passed, $fail failed =="
[[ $fail -eq 0 ]]
