# 0.4.0

Floating copies, service accounts and seats per module, on Licensebox C v0.6.0 (protocol revision 16): requiring a floating module checks a copy out, heartbeats keep it, checking in returns it (`no_free_copy` when every copy is in use); a service account enrols with a one-time token (`enrol_token` or `LICENSEBOX_ENROL_TOKEN`) without a browser (`invalid_token` when used or expired).

# 0.3.0

Protocol v3: built on Licensebox C v0.5.0, which signs and verifies with Ed25519 and ML-DSA-65 together and needs OpenSSL 3.5+. Protocol v2 keys and leases are refused.

# 0.2.0

Explicit heartbeat checkpoints with signed contact deadlines. Scheduling remains opt-in.

# 0.1.0

Initial Linux native application SDK.
