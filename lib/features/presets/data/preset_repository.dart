import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/local_db.dart';
import '../../advanced_settings/domain/advanced_settings_model.dart';

final presetRepositoryProvider = Provider<PresetRepository>((ref) {
  return PresetRepository(ref.read(databaseProvider));
});

class PresetRepository {
  final AppDatabase _db;

  PresetRepository(this._db);

  Stream<List<Preset>> watchPresets() => _db.watchPresets();
  Future<List<Preset>> getPresets() => _db.getAllPresets();

  Future<bool> canAddPreset() async {
    final count = await _db.getPresetCount();
    return count < AppConstants.maxPresets;
  }

  Future<void> createPreset({
    required String name,
    required List<String> deviceIds,
    required String protocolId,
    AdvancedSettings advancedSettings = const AdvancedSettings(),
  }) async {
    final canAdd = await canAddPreset();
    if (!canAdd) throw Exception('Maximum ${AppConstants.maxPresets} presets allowed');

    final presets = await _db.getAllPresets();
    final sortOrder = presets.isEmpty ? 0 : presets.last.sortOrder + 1;

    await _db.upsertPreset(PresetsCompanion(
      id: Value(const Uuid().v4()),
      name: Value(name),
      deviceIds: Value(jsonEncode(deviceIds)),
      protocolId: Value(protocolId),
      advancedSettingsJson: Value(advancedSettings.encode()),
      sortOrder: Value(sortOrder),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> updatePreset({
    required String id,
    String? name,
    List<String>? deviceIds,
    String? protocolId,
    AdvancedSettings? advancedSettings,
  }) async {
    await _db.upsertPreset(PresetsCompanion(
      id: Value(id),
      name: name != null ? Value(name) : const Value.absent(),
      deviceIds: deviceIds != null
          ? Value(jsonEncode(deviceIds))
          : const Value.absent(),
      protocolId:
          protocolId != null ? Value(protocolId) : const Value.absent(),
      advancedSettingsJson: advancedSettings != null
          ? Value(advancedSettings.encode())
          : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> deletePreset(String id) => _db.deletePreset(id);
}
