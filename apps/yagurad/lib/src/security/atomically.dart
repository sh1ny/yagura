import '../host/database.dart';

/// Runs [body] in a transaction, or inside the one that is already open.
T atomically<T>(YaguraDatabase database, T Function() body) =>
    database.sqlite.autocommit ? database.transaction(body) : body();
