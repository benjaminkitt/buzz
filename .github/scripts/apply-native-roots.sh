#!/usr/bin/env bash
# Make tokio-tungstenite's default root store include the OS trust store.
#
# Upstream builds tokio-tungstenite with only `rustls-tls-webpki-roots`, so the
# relay WebSocket trusts a compiled-in Mozilla root list and nothing else. Behind
# a TLS-inspecting proxy the re-signed certificate is rejected with
# `invalid peer certificate: UnknownIssuer`, and no keychain entry, SSL_CERT_FILE
# or NODE_EXTRA_CA_CERTS can influence it.
#
# The two root-store features are additive — tokio-tungstenite's tls.rs pushes
# both sets into the same RootCertStore — so adding native roots preserves the
# stock behaviour and additionally honours the platform store.
#
# Deliberately a substitution rather than a stored git patch: the target string
# is short and stable, so this survives upstream reshuffling the manifests,
# whereas a patch would conflict on any nearby edit.
set -euo pipefail

OLD='tokio-tungstenite = { version = "0.29", features = ["rustls-tls-webpki-roots"] }'
NEW='tokio-tungstenite = { version = "0.29", features = ["rustls-tls-webpki-roots", "rustls-tls-native-roots"] }'

# Root workspace drives the sidecars (buzz, buzz-acp, buzz-dev-mcp); the desktop
# workspace drives the app itself. Both need it.
FILES=(Cargo.toml desktop/src-tauri/Cargo.toml)

rc=0
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "error: $f not found (run from the repository root)" >&2
    rc=1
    continue
  fi

  if grep -qF -- "$NEW" "$f"; then
    echo "ok: $f already patched"
    continue
  fi

  count=$(grep -cF -- "$OLD" "$f" || true)
  if [[ "$count" -ne 1 ]]; then
    echo "error: expected exactly 1 occurrence of the tokio-tungstenite line in $f, found $count" >&2
    echo "       upstream probably changed the dependency declaration; update this script." >&2
    rc=1
    continue
  fi

  python3 - "$f" "$OLD" "$NEW" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as fh:
    text = fh.read()
assert text.count(old) == 1
with open(path, "w") as fh:
    fh.write(text.replace(old, new))
PY
  echo "patched: $f"
done

exit "$rc"
