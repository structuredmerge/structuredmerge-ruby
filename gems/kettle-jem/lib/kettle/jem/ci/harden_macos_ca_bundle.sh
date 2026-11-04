#!/bin/sh
# Remove the eMudhra-related roots from the macOS system CA bundle.
#
# Apple's /etc/ssl/cert.pem still carries roots from the eMudhra incident, and the
# developer tools Apple ships (git, curl, python3) read that file, so a network
# attacker could tamper with downloads made during a release build. GitHub's macOS
# runners are ephemeral, so removing the roots at job start needs no re-application
# after OS updates. Reference: https://github.com/galadran/we-have-a-problem.com/issues/157
#
# It must run BEFORE the first step that downloads anything (actions/checkout runs
# git), so the workflows inline this exact file. A contract test keeps them identical.
#
# Matching is by certificate subject so no fingerprints need to be guessed; every
# removed certificate is printed with its SHA-256 fingerprint for the audit log, and
# the script fails if any matching certificate is still present afterwards.
#
# Environment (for tests): CA_BUNDLE (default /etc/ssl/cert.pem), SUDO (default sudo).
set -eu

bundle="${CA_BUNDLE:-/etc/ssl/cert.pem}"
sudo_cmd="${SUDO-sudo}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

matches() {
  case "$1" in
    *"AAA Certificate Services"* | *"emSign ECC Root CA - G3"* | *[eE][mM]udhra*) return 0 ;;
    *) return 1 ;;
  esac
}

total="$(grep -c -- '-----BEGIN CERTIFICATE-----' "$bundle")"
[ "$total" -ge 100 ] || { echo "refusing to edit $bundle: only $total certificates" >&2; exit 1; }

awk -v dir="$work" '
  /-----BEGIN CERTIFICATE-----/ { if (out != "") close(out); n++; out = dir "/c" n ".pem" }
  out != "" { print > out }
' "$bundle"

: > "$work/clean.pem"
removed=0
i=1
while [ "$i" -le "$total" ]; do
  file="$work/c$i.pem"
  subject="$(openssl x509 -in "$file" -noout -subject 2>/dev/null || true)"
  if [ -n "$subject" ] && matches "$subject"; then
    fingerprint="$(openssl x509 -in "$file" -noout -fingerprint -sha256)"
    echo "removing: $subject ($fingerprint)"
    removed=$((removed + 1))
  else
    cat "$file" >> "$work/clean.pem"
  fi
  i=$((i + 1))
done

if [ "$removed" -gt 0 ]; then
  $sudo_cmd tee "$bundle" < "$work/clean.pem" > /dev/null
fi

# Verify what is on disk now, not what we intended to write.
after="$(grep -c -- '-----BEGIN CERTIFICATE-----' "$bundle")"
[ "$after" -eq $((total - removed)) ] || { echo "certificate count mismatch: $after != $total - $removed" >&2; exit 1; }
rm -f "$work"/c*.pem
awk -v dir="$work" '
  /-----BEGIN CERTIFICATE-----/ { if (out != "") close(out); n++; out = dir "/v" n ".pem" }
  out != "" { print > out }
' "$bundle"
for file in "$work"/v*.pem; do
  subject="$(openssl x509 -in "$file" -noout -subject 2>/dev/null || true)"
  if [ -n "$subject" ] && matches "$subject"; then
    echo "still trusted after cleanup: $subject" >&2
    exit 1
  fi
done
echo "CA bundle $bundle: $total certificates, removed $removed, $after remain."
