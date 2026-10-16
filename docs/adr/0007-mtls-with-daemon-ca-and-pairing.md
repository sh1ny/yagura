# 0007. mTLS with a daemon-local CA and one-time pairing codes

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
The daemon controls processes, files and firewall rules on the host, so its API is effectively admin access. Hosts are reached over LANs, VPNs or forwarded ports. There is no central account system and none is wanted.

## Decision
On first start the daemon creates a daemon id, a private CA (ECDSA P-256, 20 years) and a server certificate signed by it whose SAN is the fixed name `garrisond-<daemon-id>` plus `localhost` (2 years, rotated at startup when under 30 days remain). Clients connect by any address but verify the server against the pinned CA with the TLS authority set to that fixed name, so the network address never matters. Pairing: the admin runs `garrisond pair`, which asks the running service over the local admin channel (ADR 0012) and prints a pairing string: address, a single-use code valid for 10 minutes, and the SHA-256 fingerprint of the CA. The client calls `Pairing.Info`, which returns the CA certificate; it checks the certificate's SHA-256 against the fingerprint, then uses it as the only trusted root and calls `Pairing.Enroll` with the code, a device name and a CSR for a key it generated and keeps in the OS keychain. The daemon checks the code, signs a client certificate (1-year validity), records the device and returns it. From then on every call uses mTLS: the listener requests client certificates and verifies them against the CA, an interceptor rejects any call without one (fail-closed, tested per method) and checks that the presented certificate's SHA-256 fingerprint (Dart's `X509Certificate` exposes the DER, not the serial) belongs to an enrolled, non-revoked device, so revocation takes effect on the next call without a CA rebuild. Devices renew their certificate before expiry over their existing mTLS connection (`Pairing.RenewCertificate`). Only `Pairing.Enroll` and `Pairing.Info` accept a connection without a client certificate. A localhost-only plaintext dev mode exists for development and is refused on any non-loopback address. Certificate creation and signing use the `x509` package (`TbsCertificate`, `Signer`), proven by an early spike; a fallback is a minimal DER builder over `pointycastle`.

**Rejected: a long-lived bearer token over server-only TLS.** Simpler, but a leaked token works from anywhere and the client must also pin the server another way.

**Rejected: pinned self-signed certificates on both ends.** No signing code, but adding or revoking a device means rebuilding the server's trust store and rebinding the listener.

**Reversal cost: medium.** Changing trust means re-pairing every device; the API surface is unaffected.

## Consequences
- The CA key is the crown jewel: DPAPI-protected (ADR 0011), never exported.
- All devices have full rights in v1; roles would add a claim to the device record, not change the scheme.
- Clock skew larger than certificate leeway breaks connections; validity starts 1 hour in the past.
