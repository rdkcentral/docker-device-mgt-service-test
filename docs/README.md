# Documentation Index

Technical documentation for the **docker-device-mgt-service-test** harness.

This test harness runs two Docker containers that simulate an RDK device and its
management cloud, exercising the certificate / mTLS / PKI flow between them:

- **mock-xconf** — the server side (mock XConf / cloud services)
- **native-platform** — the device / client side

## Certificate Subsystem (security team)

The certificate documentation lives under [certificates/](certificates/README.md)
and covers the full cross-container mTLS/PKI flow:

- [Overview](certificates/README.md)
- [Architecture](certificates/architecture.md)
- [Certificate Lifecycle](certificates/certificate-lifecycle.md)
- [Shared-Volume Contract](certificates/shared-volume-contract.md)
- [Configuration Reference](certificates/configuration.md)
- [PKCS#11 / SoftHSM](certificates/pkcs11.md)
- [xPKI Certifier Service](certificates/xpki-certifier.md)
- [Troubleshooting](certificates/troubleshooting.md)

> **Scope note.** This documentation set describes the certificate subsystem as
> currently merged (brownfield). Platform-owned areas (RFC providers,
> tr69hostif, log upload, DCM) are documented separately by the platform team.
