/// Nostr event kinds used by this SDK.
abstract final class NostrTodoKinds {
  static const int todo = 713;
  static const int todoStatus = 714;
  static const int deletion = 5;
}

/// Default relays used when no NIP-65 write relays are available.
abstract final class NostrTodoDefaultRelays {
  static const List<String> fallbackBroadcastRelays = [
    'wss://nos.lol',
    'wss://relay.damus.io',
    'wss://relay.primal.net',
    'wss://relay.nmail.li',
    'wss://nostr-01.yakihonne.com',
  ];
}
