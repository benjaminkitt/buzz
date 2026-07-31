# Fork notes

This is a fork of [block/buzz](https://github.com/block/buzz), maintained for one
purpose: to publish builds that work behind a TLS-inspecting corporate proxy.

## The change

Modified files, per Apache-2.0 §4(b):

- `Cargo.toml` — root workspace
- `desktop/src-tauri/Cargo.toml` — desktop workspace

In both, the `tokio-tungstenite` dependency gains the `rustls-tls-native-roots`
feature alongside the existing `rustls-tls-webpki-roots`:

```diff
-tokio-tungstenite = { version = "0.29", features = ["rustls-tls-webpki-roots"] }
+tokio-tungstenite = { version = "0.29", features = ["rustls-tls-webpki-roots", "rustls-tls-native-roots"] }
```

Applied by `.github/scripts/apply-native-roots.sh`. Nothing else is changed.

## Why

Upstream builds `tokio-tungstenite` with only `rustls-tls-webpki-roots`, and
`desktop/src-tauri/src/native_websocket.rs` calls bare `connect_async()` with no
custom `Connector`. The relay WebSocket therefore trusts a compiled-in Mozilla
root list and nothing else — not the macOS keychain, not `SSL_CERT_FILE`, not
`NODE_EXTRA_CA_CERTS`.

Behind a TLS-inspecting proxy (Netskope, Zscaler, Palo Alto, …) the relay's
certificate is re-signed by a corporate CA, and the connection fails with:

```
invalid peer certificate: UnknownIssuer
```

This is invisible in most of the app because HTTPS requests go through `reqwest`,
which uses `rustls-platform-verifier` and *does* read the OS trust store. Only
the WebSocket path is affected, so the app appears healthy right up until the
relay never connects. The sidecars `buzz`, `buzz-acp` and `buzz-dev-mcp` share
the root workspace dependency and fail the same way; `buzz-agent` uses
`reqwest` only and is unaffected.

The two root-store features are additive — tokio-tungstenite's `tls.rs` pushes
both sets into a single `RootCertStore`, and the webpki branch is not gated on
`not(rustls-tls-native-roots)` — so this preserves upstream behaviour for the
public web and additionally honours the platform store.

Measured against a real proxied relay: `webpki-roots only => UnknownIssuer`,
`native + webpki roots => connected`, with 148 additional roots loaded from the
keychain.

## How these builds differ from upstream's

`.github/workflows/fork-release.yml` rebuilds upstream's macOS (arm64) and Linux
artifacts. Upstream's `release.yml` is guarded with
`if: github.repository == 'block/buzz'` and needs Block's secrets, so it cannot
run here. Consequences:

- **Unsigned and un-notarized.** No Apple Developer ID. The macOS bundle is
  ad-hoc signed only, so macOS will re-prompt for keychain, camera and
  microphone access, and Gatekeeper will object if the DMG is downloaded through
  a browser. The hardened runtime and the `Entitlements.plist` entitlements are
  not applied; without a Developer ID they would add nothing, TCC prompts come
  from the `Info.plist` usage descriptions, and library validation is not
  enforced unless the hardened runtime is on.
- **No self-updater.** Upstream's updater config needs signing keys. These builds
  have no updater, which suits a package-manager-managed install.
- **arm64 macOS and x86_64 Linux only.** No Intel macOS, no Windows.

Release tags match upstream's (`v0.5.0`, …) but are **only version markers**:
they are created at this fork's default branch, and the commit a tag names is
*not* the build source. The patch is applied to a throwaway working tree during
the build and is never committed. Each release's notes record the exact upstream
commit it was built from — that is the authoritative provenance.

That indirection is forced rather than chosen. The default `GITHUB_TOKEN` is a
GitHub App token, and GitHub rejects any push whose ref introduces a created or
updated file under `.github/workflows` without the `workflows` permission, which
App tokens cannot hold. Upstream edits its own workflows between releases, so
pushing a tag at a new upstream commit fails with:

```
refusing to allow a GitHub App to create or update workflow
`.github/workflows/linux-canary.yml` without `workflows` permission
```

Creating the tag through the REST API instead is a ref creation rather than a
push, and is unaffected — but it can only target a commit reachable from a fork
ref. Pointing a tag at the upstream release commit is refused with
`HTTP 403: Resource not accessible by integration`, even though the object
resolves through the shared fork network.

Making tags name the real build source would need a PAT or deploy key with
`workflows` write access stored as a repository secret. That is the only thing
the current setup gives up, and the release notes cover it.

## Upstreaming

The intent is for this fork to become unnecessary. The change has been proposed
upstream; if it lands, these builds should be abandoned in favour of official
signed releases.
