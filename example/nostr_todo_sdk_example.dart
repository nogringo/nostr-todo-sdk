import 'package:nostr_todo_sdk/nostr_todo_sdk.dart';
import 'package:ndk/ndk.dart';
import 'package:sembast/sembast_memory.dart';

void main() async {
  // Initialize in-memory database for example
  final db = await databaseFactoryMemory.openDatabase('example.db');

  // Initialize NDK
  final ndk = Ndk(
    NdkConfig(cache: MemCacheManager(), eventVerifier: Bip340EventVerifier()),
  );

  // Login with a private key (example - use secure storage in production)
  // This is just for demonstration
  ndk.accounts.loginPrivateKey(
    pubkey: "b8b7d8681855c33abac83c7f022058d74f2d66fdb5eff1e137d15efecc29a3e6",
    privkey: "1206809c7dce1ddf4915eb9a7388a001ca7f66395d4bb2c2a50335892fc2c2ce",
  );

  // Create TodoService instance - automatically starts listening to todo events
  final todoService = TodoService(ndk: ndk, db: db);

  // Example: Create a todo
  final todo = await todoService.createTodo(
    description: 'Buy groceries',
    encrypted: false,
  );
  print('Created todo: ${todo.description} (Status: ${todo.status})');

  // Example: Start working on a todo
  await todoService.startTodo(id: todo.eventId);
  print('Started todo: ${todo.eventId}');

  // Example: Complete a todo
  await todoService.completeTodo(id: todo.eventId);
  print('Completed todo: ${todo.eventId}');

  // Example: Update todo status directly
  await todoService.updateTodoStatus(
    id: todo.eventId,
    status: TodoStatus.doing,
  );
  print('Updated todo status to: doing');

  // Example: Block a todo
  await todoService.blockTodo(id: todo.eventId);
  print('Blocked todo: ${todo.eventId}');

  // Example: Get todos by status
  final pendingTodos = await todoService.getPendingTodos();
  print('Pending todos: ${pendingTodos.length}');

  final inProgressTodos = await todoService.getInProgressTodos();
  print('In-progress todos: ${inProgressTodos.length}');

  final completedTodos = await todoService.getCompletedTodos();
  print('Completed todos: ${completedTodos.length}');

  final blockedTodos = await todoService.getBlockedTodos();
  print('Blocked todos: ${blockedTodos.length}');

  // Example: Remove todo status (return to pending)
  await todoService.removeTodoStatus(id: todo.eventId);
  print('Removed todo status, back to pending');

  // Example: Switch to a different account
  ndk.accounts.logout();
  ndk.accounts.loginPrivateKey(
    pubkey: "different_pubkey_here",
    privkey: "different_privkey_here",
  );

  // IMPORTANT: Notify TodoService about auth state change
  todoService.onAuthStateChanged();

  // Now the service is listening to the new user's events

  // When done, clean up
  todoService.stopListening();
}
