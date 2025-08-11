import 'package:nostr_todo_sdk/nostr_todo_sdk.dart';
import 'package:ndk/ndk.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/sembast.dart' as sembast;
import 'package:test/test.dart';

void main() {
  test('should create and complete a todo', () async {
    // Setup
    final db = await databaseFactoryMemory.openDatabase('test.db');

    final ndk = Ndk(
      NdkConfig(
        cache: MemCacheManager(),
        eventVerifier: Bip340EventVerifier(),
        bootstrapRelays: ["ws://localhost:7777"],
      ),
    );

    // Login with real Nostr keypair
    ndk.accounts.loginPrivateKey(
      pubkey: 'b8b7d8681855c33abac83c7f022058d74f2d66fdb5eff1e137d15efecc29a3e6',
      privkey: '1206809c7dce1ddf4915eb9a7388a001ca7f66395d4bb2c2a50335892fc2c2ce',
    );

    final todoService = TodoService(ndk: ndk, db: db);

    // Create a todo
    final todo = await todoService.createTodo(
      description: 'Buy groceries',
      encrypted: false,
    );

    // Verify the todo was created correctly
    expect(todo.description, equals('Buy groceries'));
    expect(todo.isCompleted, isFalse);
    expect(todo.eventId, isNotEmpty);
    expect(todo.createdAt, isA<DateTime>());

    // Verify it was stored in the database
    final storedEvent = await todoService.todoEventsStore
        .record(todo.eventId)
        .get(db);
    expect(storedEvent, isNotNull);
    expect(storedEvent!['decryptedContent'], equals('Buy groceries'));

    // Mark it as completed
    await todoService.completeTodo(id: todo.eventId);

    // Verify a status event was created
    final statusEvents = await todoService.todoEventsStore.find(db,
      finder: sembast.Finder(
        filter: sembast.Filter.and([
          sembast.Filter.equals('nostrEvent.kind', TodoService.kindTodoStatus),
          sembast.Filter.equals('nostrEvent.content', 'DONE'),
        ]),
      ),
    );

    expect(statusEvents, isNotEmpty);
    
    // Verify the status event references the correct todo
    final statusEvent = statusEvents.first.value['nostrEvent'];
    final tags = statusEvent['tags'] as List;
    final hasCorrectTag = tags.any((tag) => 
      tag is List && tag.length == 2 && tag[0] == 'e' && tag[1] == todo.eventId
    );
    expect(hasCorrectTag, isTrue);

    // Get todos and verify it's marked as completed
    final todos = await todoService.getTodos();
    final completedTodo = todos.firstWhere((t) => t.eventId == todo.eventId);
    expect(completedTodo.isCompleted, isTrue);

    // Cleanup
    todoService.dispose();
    await db.close();
  });
}
