## 1.2.0

- BREAKING: require callers to provide an `OfflineBroadcast` queue to `TodoService`.
- BREAKING: make `TodoService.dispose()` asynchronous.
- Add offline-first broadcast queue support.
- Respect NIP-65 write relays when broadcasting todo events, with default fallback relays.
- Add `k` tags to deletion events and filter deletion subscriptions by todo kinds.
- Add Nostr todo constants for event kinds and default fallback relays.
- Use NDK mock relay in tests.

## 1.1.0

- add statuses
