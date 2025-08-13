import 'dart:async';
import 'package:ndk/ndk.dart';
import 'package:sembast/sembast.dart' as sembast;
import '../models/todo.dart';

class TodoService {
  static const int kindTodo = 713;
  static const int kindTodoStatus = 714;
  static const int kindDeletion = 5;

  final Ndk ndk;
  final sembast.Database db;
  final sembast.StoreRef<String, Map<String, dynamic>> todoEventsStore;
  final sembast.StoreRef<String, bool> deletedEventsStore;
  NdkResponse? _subscription;

  // Stream controller for todo changes (emits void events)
  final _controller = StreamController<void>.broadcast();
  Stream<void> get stream => _controller.stream;

  String? get pubkey => ndk.accounts.getPublicKey();

  TodoService({required this.ndk, required this.db})
    : todoEventsStore = sembast.stringMapStoreFactory.store('todo_events'),
      deletedEventsStore = sembast.StoreRef<String, bool>.main() {
    _startListening();
  }

  void _startListening() {
    final currentPubkey = pubkey;
    if (currentPubkey == null) return;

    _subscription = ndk.requests.subscription(
      filters: [
        Filter(
          kinds: [kindDeletion, kindTodo, kindTodoStatus],
          authors: [currentPubkey],
        ),
      ],
      cacheRead: true,
      cacheWrite: true,
    );

    _subscription!.stream.listen((event) async {
      await processIncomingEvent(event);
    });
  }

  void stopListening() {
    if (_subscription != null) {
      ndk.requests.closeSubscription(_subscription!.requestId);
      _subscription = null;
    }
  }

  /// Call this method when authentication state changes (login, logout, account switch)
  /// This will stop the current subscription and start listening to the new user's events
  void onAuthStateChanged() {
    // Stop current subscription
    stopListening();

    // Clear local cache for the previous user (optional - depends on your requirements)
    // You might want to keep the cache if switching back to the same user

    // Start listening with the new user
    _startListening();
  }

  /// Dispose of the TodoService and clean up resources
  /// Call this when the service is no longer needed
  void dispose() {
    stopListening();
    _controller.close();
    // Note: We don't close the database here as it might be shared with other services
    // The caller is responsible for closing the database when appropriate
  }

  Future<void> processIncomingEvent(Nip01Event event) async {
    print("event");
    if (event.kind == kindDeletion) {
      // Handle deletion
      List<String> targetEventIds = event.getTags("e");
      for (var id in targetEventIds) {
        await deletedEventsStore.record(id).put(db, true);
        await todoEventsStore.record(id).delete(db);
      }
      _controller.add(null); // Emit change
    } else {
      // Check if deleted
      final isDeleted = await deletedEventsStore.record(event.id).get(db);
      if (isDeleted != null && isDeleted) {
        return;
      }

      // Check if exists
      final existingEvent = await todoEventsStore.record(event.id).get(db);
      if (existingEvent != null) {
        return;
      }

      if (event.kind == kindTodo) {
        // Decrypt if needed
        String decryptedContent = event.content;
        if (event.tags.any((tag) => tag.length >= 2 && tag[0] == 'encrypted')) {
          try {
            decryptedContent =
                await ndk.accounts.getLoggedAccount()!.signer.decryptNip44(
                  ciphertext: event.content,
                  senderPubKey: pubkey!,
                ) ??
                '';
          } catch (e) {
            decryptedContent = '';
          }
        }

        await todoEventsStore.record(event.id).put(db, {
          'nostrEvent': event.toJson(),
          'decryptedContent': decryptedContent,
        });
        _controller.add(null); // Emit change
      } else if (event.kind == kindTodoStatus) {
        await todoEventsStore.record(event.id).put(db, {
          'nostrEvent': event.toJson(),
          'decryptedContent': null,
        });
        _controller.add(null); // Emit change
      }
    }
  }

  Future<Todo> createTodo({
    required String description,
    bool encrypted = false,
  }) async {
    final currentPubkey = pubkey;
    if (currentPubkey == null) {
      throw Exception('No logged in user');
    }

    String content = description;

    if (encrypted) {
      // Encrypt content using NIP-44
      final encryptedContent = await ndk.accounts
          .getLoggedAccount()!
          .signer
          .encryptNip44(plaintext: description, recipientPubKey: currentPubkey);
      content = encryptedContent ?? description;
    }

    final event = Nip01Event(
      pubKey: currentPubkey,
      kind: kindTodo,
      content: content,
      tags: encrypted
          ? [
              ['encrypted', 'NIP-44'],
            ]
          : [],
    );

    // Store locally first (offline-first)
    await todoEventsStore.record(event.id).put(db, {
      'nostrEvent': event.toJson(),
      'decryptedContent': description,
    });

    // Broadcast to network
    ndk.broadcast.broadcast(nostrEvent: event);

    _controller.add(null); // Emit change

    return Todo(
      eventId: event.id,
      description: description,
      createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
      status: TodoStatus.pending,
    );
  }

  Future<void> updateTodoStatus({
    required String id,
    required TodoStatus status,
  }) async {
    final currentPubkey = pubkey;
    if (currentPubkey == null) return;

    // Don't create status event for pending status
    if (status == TodoStatus.pending) {
      await removeTodoStatus(id: id);
      return;
    }

    String statusContent;
    switch (status) {
      case TodoStatus.doing:
        statusContent = 'DOING';
        break;
      case TodoStatus.done:
        statusContent = 'DONE';
        break;
      case TodoStatus.blocked:
        statusContent = 'BLOCKED';
        break;
      default:
        return; // Don't create status for pending
    }

    final event = Nip01Event(
      pubKey: currentPubkey,
      kind: kindTodoStatus,
      content: statusContent,
      tags: [
        ['e', id],
      ],
    );

    // Store locally first
    await todoEventsStore.record(event.id).put(db, {
      'nostrEvent': event.toJson(),
      'decryptedContent': null,
    });

    // Broadcast to network
    ndk.broadcast.broadcast(nostrEvent: event);

    _controller.add(null); // Emit change
  }

  Future<void> completeTodo({required String id}) async {
    await updateTodoStatus(id: id, status: TodoStatus.done);
  }

  Future<void> startTodo({required String id}) async {
    await updateTodoStatus(id: id, status: TodoStatus.doing);
  }

  Future<void> blockTodo({required String id}) async {
    await updateTodoStatus(id: id, status: TodoStatus.blocked);
  }

  /// Remove the status of a todo (returns it to pending state)
  Future<void> removeTodoStatus({required String id}) async {
    final currentPubkey = pubkey;
    if (currentPubkey == null) return;

    // Find all status events for this user
    final finder = sembast.Finder(
      filter: sembast.Filter.and([
        sembast.Filter.equals('nostrEvent.kind', kindTodoStatus),
        sembast.Filter.equals('nostrEvent.pubkey', currentPubkey),
      ]),
    );

    final statusEvents = await todoEventsStore.find(db, finder: finder);

    // Filter and delete status events for this specific todo
    for (var record in statusEvents) {
      final nostrEvent = record.value['nostrEvent'];
      final tags = nostrEvent['tags'] as List;

      // Check if this status event is for our todo
      bool isForThisTodo = false;
      for (var tag in tags) {
        if (tag is List && tag.length > 1 && tag[0] == 'e' && tag[1] == id) {
          isForThisTodo = true;
          break;
        }
      }

      if (isForThisTodo) {
        final statusEventId = nostrEvent['id'] as String;

        // Mark as deleted locally
        await deletedEventsStore.record(statusEventId).put(db, true);
        await todoEventsStore.record(statusEventId).delete(db);

        // Broadcast deletion to network
        ndk.broadcast.broadcastDeletion(eventId: statusEventId);
      }
    }

    _controller.add(null); // Emit change
  }

  Future<void> deleteTodo({required String id}) async {
    await deleteTodos(ids: [id]);
  }

  /// Delete multiple todos and their related status events at once
  Future<void> deleteTodos({required List<String> ids}) async {
    final currentPubkey = pubkey;
    if (currentPubkey == null) return;

    if (ids.isEmpty) return;

    List<String> eventIdsToDelete = [...ids]; // Start with the todo IDs

    // Find all status events for this user
    final finder = sembast.Finder(
      filter: sembast.Filter.and([
        sembast.Filter.equals('nostrEvent.kind', kindTodoStatus),
        sembast.Filter.equals('nostrEvent.pubkey', currentPubkey),
      ]),
    );
    final statusEvents = await todoEventsStore.find(db, finder: finder);

    // Find status events related to any of the todos being deleted
    for (var record in statusEvents) {
      final nostrEvent = record.value['nostrEvent'];
      final tags = nostrEvent['tags'] as List;
      for (var tag in tags) {
        if (tag is List &&
            tag.length > 1 &&
            tag[0] == 'e' &&
            ids.contains(tag[1])) {
          eventIdsToDelete.add(nostrEvent['id']);
        }
      }
    }

    // Store deletions locally first
    for (var eventId in eventIdsToDelete) {
      await deletedEventsStore.record(eventId).put(db, true);
      await todoEventsStore.record(eventId).delete(db);
    }

    // Create a single deletion event with all IDs (more efficient than multiple broadcasts)
    if (eventIdsToDelete.isNotEmpty) {
      final deleteEvent = Nip01Event(
        pubKey: currentPubkey,
        kind: kindDeletion,
        content: '',
        tags: eventIdsToDelete.map((id) => ['e', id]).toList(),
      );

      ndk.broadcast.broadcast(nostrEvent: deleteEvent);
    }

    _controller.add(null); // Emit change
  }

  Future<List<Todo>> getTodos() async {
    final currentPubkey = pubkey;
    if (currentPubkey == null) return [];

    List<Todo> result = [];

    // Get all todo events for current user
    final finder = sembast.Finder(
      filter: sembast.Filter.equals('nostrEvent.pubkey', currentPubkey),
    );
    final records = await todoEventsStore.find(db, finder: finder);

    // Build status map (keep only the latest status for each todo)
    Map<String, TodoStatus> statusMap = {};
    Map<String, int> statusTimestamps = {};

    for (var record in records) {
      final data = record.value;
      final nostrEvent = data['nostrEvent'];

      if (nostrEvent['kind'] == kindTodoStatus) {
        final tags = nostrEvent['tags'] as List;
        String? todoId;
        for (var tag in tags) {
          if (tag is List && tag.length > 1 && tag[0] == 'e') {
            todoId = tag[1];
            break;
          }
        }

        if (todoId != null) {
          final timestamp = nostrEvent['created_at'] as int;
          // Only update if this is newer than the existing status
          if (!statusTimestamps.containsKey(todoId) ||
              statusTimestamps[todoId]! < timestamp) {
            statusTimestamps[todoId] = timestamp;

            if (nostrEvent['content'] == 'DOING') {
              statusMap[todoId] = TodoStatus.doing;
            } else if (nostrEvent['content'] == 'DONE') {
              statusMap[todoId] = TodoStatus.done;
            } else if (nostrEvent['content'] == 'BLOCKED') {
              statusMap[todoId] = TodoStatus.blocked;
            }
          }
        }
      }
    }

    // Build todo list
    for (var record in records) {
      final data = record.value;
      final nostrEvent = data['nostrEvent'];

      if (nostrEvent['kind'] == kindTodo) {
        final decryptedContent = data['decryptedContent'] ?? '';

        result.add(
          Todo(
            eventId: nostrEvent['id'],
            description: decryptedContent,
            status: statusMap[nostrEvent['id']] ?? TodoStatus.pending,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              nostrEvent['created_at'] * 1000,
            ),
          ),
        );
      }
    }

    // Sort todos
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return result;
  }

  /// Get todos by status
  Future<List<Todo>> getTodosByStatus(TodoStatus status) async {
    final allTodos = await getTodos();
    return allTodos.where((todo) => todo.status == status).toList();
  }

  /// Get only completed todos
  Future<List<Todo>> getCompletedTodos() async {
    return getTodosByStatus(TodoStatus.done);
  }

  /// Get pending todos
  Future<List<Todo>> getPendingTodos() async {
    return getTodosByStatus(TodoStatus.pending);
  }

  /// Get in-progress todos
  Future<List<Todo>> getInProgressTodos() async {
    return getTodosByStatus(TodoStatus.doing);
  }

  /// Get blocked todos
  Future<List<Todo>> getBlockedTodos() async {
    return getTodosByStatus(TodoStatus.blocked);
  }
}
