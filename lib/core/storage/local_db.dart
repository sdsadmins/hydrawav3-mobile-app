import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_db.g.dart';

// --- Table Definitions ---

class PairedDevices extends Table {
  TextColumn get id => text()();
  TextColumn get macAddress => text().unique()();
  TextColumn get name => text()();
  BoolColumn get autoReconnect => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastConnected => dateTime().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedProtocols extends Table {
  TextColumn get id => text()();
  TextColumn get templateName => text()();
  IntColumn get sessions => integer().withDefault(const Constant(1))();
  TextColumn get cyclesJson => text()(); // JSON-encoded cycles array
  RealColumn get hotdrop => real().withDefault(const Constant(0.0))();
  RealColumn get colddrop => real().withDefault(const Constant(0.0))();
  RealColumn get vibmin => real().withDefault(const Constant(0.0))();
  RealColumn get vibmax => real().withDefault(const Constant(0.0))();
  BoolColumn get cycle1 => boolean().withDefault(const Constant(false))();
  BoolColumn get cycle5 => boolean().withDefault(const Constant(false))();
  RealColumn get edgecycleduration =>
      real().withDefault(const Constant(0.0))();
  RealColumn get sessionPause => real().withDefault(const Constant(0.0))();
  TextColumn get description => text().withDefault(const Constant(''))();
  DateTimeColumn get cachedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalSessions extends Table {
  TextColumn get id => text()();
  TextColumn get protocolId => text()();
  TextColumn get protocolName => text()();
  TextColumn get deviceIds => text()(); // JSON-encoded list
  IntColumn get durationSeconds => integer()();
  IntColumn get elapsedSeconds => integer()();
  IntColumn get discomfortBefore => integer().nullable()();
  IntColumn get discomfortAfter => integer().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Presets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get deviceIds => text()(); // JSON-encoded list
  TextColumn get protocolId => text()();
  TextColumn get advancedSettingsJson =>
      text().withDefault(const Constant('{}'))(); // JSON
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class CommandQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get macAddress => text()();
  TextColumn get commandJson => text()(); // JSON-encoded command
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

// --- Database Definition ---

@DriftDatabase(tables: [
  PairedDevices,
  CachedProtocols,
  LocalSessions,
  Presets,
  CommandQueue,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // --- Paired Devices ---
  Future<List<PairedDevice>> getAllPairedDevices() =>
      select(pairedDevices).get();

  Stream<List<PairedDevice>> watchPairedDevices() =>
      select(pairedDevices).watch();

  Future<void> upsertPairedDevice(PairedDevicesCompanion device) =>
      into(pairedDevices).insertOnConflictUpdate(device);

  Future<void> removePairedDevice(String macAddress) =>
      (delete(pairedDevices)
            ..where((t) => t.macAddress.equals(macAddress)))
          .go();

  // --- Cached Protocols ---
  Future<List<CachedProtocol>> getAllCachedProtocols() =>
      select(cachedProtocols).get();

  Stream<List<CachedProtocol>> watchCachedProtocols() =>
      select(cachedProtocols).watch();

  Future<CachedProtocol?> getCachedProtocol(String id) =>
      (select(cachedProtocols)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsertProtocol(CachedProtocolsCompanion protocol) =>
      into(cachedProtocols).insertOnConflictUpdate(protocol);

  Future<void> clearProtocolCache() => delete(cachedProtocols).go();

  // --- Local Sessions ---
  Future<List<LocalSession>> getAllLocalSessions() =>
      (select(localSessions)
            ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]))
          .get();

  Stream<List<LocalSession>> watchLocalSessions() =>
      (select(localSessions)
            ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]))
          .watch();

  Future<List<LocalSession>> getUnsyncedSessions() =>
      (select(localSessions)..where((t) => t.synced.equals(false))).get();

  Future<void> insertSession(LocalSessionsCompanion session) =>
      into(localSessions).insert(session);

  Future<void> markSessionSynced(String id) =>
      (update(localSessions)..where((t) => t.id.equals(id)))
          .write(const LocalSessionsCompanion(synced: Value(true)));

  // --- Presets ---
  Future<List<Preset>> getAllPresets() =>
      (select(presets)..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();

  Stream<List<Preset>> watchPresets() =>
      (select(presets)..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  Future<void> upsertPreset(PresetsCompanion preset) =>
      into(presets).insertOnConflictUpdate(preset);

  Future<void> deletePreset(String id) =>
      (delete(presets)..where((t) => t.id.equals(id))).go();

  Future<int> getPresetCount() async {
    final count = countAll();
    final query = selectOnly(presets)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count)!;
  }

  // --- Command Queue ---
  Future<List<CommandQueueData>> getUnsyncedCommands() =>
      (select(commandQueue)..where((t) => t.synced.equals(false))).get();

  Future<void> insertCommand(CommandQueueCompanion command) =>
      into(commandQueue).insert(command);

  Future<void> markCommandSynced(int id) =>
      (update(commandQueue)..where((t) => t.id.equals(id)))
          .write(const CommandQueueCompanion(synced: Value(true)));

  Future<void> clearSyncedCommands() =>
      (delete(commandQueue)..where((t) => t.synced.equals(true))).go();
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'hydrawav3.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});
