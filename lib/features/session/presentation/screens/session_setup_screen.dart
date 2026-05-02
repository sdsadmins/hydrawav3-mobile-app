import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/utils/extensions.dart';
import '../../../advanced_settings/domain/advanced_settings_model.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../../presets/data/preset_repository.dart';
import '../../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../../session/domain/session_model.dart';
import '../../services/session_engine.dart';

// This screen is the “web-like” setup:
// 1) One card per device.
// 2) Each device picks its own protocol.
// 3) Each device edits its own advanced settings.
// 4) “Start Session” boots SessionEngine and navigates to SessionScreen.
class SessionSetupScreen extends ConsumerStatefulWidget {
  final List<String> deviceIds;
  final String transport; // 'ble' or 'wifi'

  const SessionSetupScreen({
    super.key,
    required this.deviceIds,
    this.transport = 'ble',
  });

  @override
  ConsumerState<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends ConsumerState<SessionSetupScreen> {
  final Map<String, String> _protocolIdByDeviceId = {};
  final Map<String, AdvancedSettings> _settingsByDeviceId = {};
  String? _activeDeviceId;
  String? _delayedDeviceId;
  bool _showSavePreset = false;
  bool _starting = false;
  final Map<String, bool> _showAdvancedByDeviceId = {};

  final Map<String, String> _deviceLabelById = {};

  static const Map<int, int> _hotPwmToLevel = {
    0: 0,
    50: 1,
    55: 2,
    60: 3,
    65: 4,
    70: 5,
    75: 6,
    80: 7,
    85: 8,
    90: 9,
    95: 10,
    100: 11,
  };

  static const Map<int, int> _coldPwmToLevel = {
    0: 0,
    150: 1,
    160: 2,
    170: 3,
    180: 4,
    190: 5,
    200: 6,
    210: 7,
    220: 8,
    230: 9,
    240: 10,
    250: 11,
  };

  int _nearestLevel(int pwm, Map<int, int> map, int fallback) {
    if (map.containsKey(pwm)) return map[pwm]!;
    var bestKey = map.keys.first;
    var bestDiff = (pwm - bestKey).abs();
    for (final k in map.keys) {
      final d = (pwm - k).abs();
      if (d < bestDiff) {
        bestDiff = d;
        bestKey = k;
      }
    }
    return map[bestKey] ?? fallback;
  }

  AdvancedSettings _advancedDefaultsFromProtocol(Protocol p) {
    final first = p.cycles.isNotEmpty ? p.cycles.first : null;
    final hotLevel =
        _nearestLevel(first?.hotPwm.toInt() ?? 70, _hotPwmToLevel, 5);
    final coldLevel =
        _nearestLevel(first?.coldPwm.toInt() ?? 190, _coldPwmToLevel, 5);

    return AdvancedSettings(
      lights: true,
      vibrationMode: 'Sweep',
      vibrationSweepMin: p.vibmin,
      vibrationSweepMax: p.vibmax,
      vibrationSingleHz: 100,
      cycle1Initiation: p.cycle1,
      cycle5Completion: p.cycle5,
      hotLevel: hotLevel,
      coldLevel: coldLevel,
      hotPack: false,
      coldPack: false,
      hotDrop: p.hotdrop,
      coldDrop: p.colddrop,
      vibMin: p.vibmin,
      vibMax: p.vibmax,
      startDelay: 0,
      flipSettings: false,
    );
  }

  @override
  void initState() {
    super.initState();
    _activeDeviceId =
        widget.deviceIds.isNotEmpty ? widget.deviceIds.first : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDeviceNames());
  }

  Future<void> _loadDeviceNames() async {
    try {
      final transport = widget.transport;
      final map = <String, String>{};
      if (transport == 'ble') {
        final paired = await ref.read(bleRepositoryProvider).getPairedDevices();
        for (final p in paired) {
          map[p.macAddress.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '')] =
              p.name;
        }
      } else {
        final wifiDevices = await ref.read(wifiDevicesByOrgProvider.future);
        for (final d in wifiDevices) {
          map[d.macAddress.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '')] =
              d.name;
        }
      }
      if (!mounted) return;
      setState(() => _deviceLabelById
        ..clear()
        ..addAll(map));
    } catch (_) {
      // Keep labels as ids if loading fails.
    }
  }

  String _labelFor(String id) {
    final key = id.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    return _deviceLabelById[key] ?? id;
  }

  @override
  Widget build(BuildContext context) {
    final protocolsAsync = ref.watch(protocolListProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        title: const Text('Session Setup'),
      ),
      body: protocolsAsync.when(
        loading: () => const Center(child: HwLoading()),
        error: (e, _) => Center(
          child: Text('Failed to load protocols: $e'),
        ),
        data: (protocols) {
          final allSelected = widget.deviceIds.isNotEmpty &&
              widget.deviceIds.every((id) =>
                  _protocolIdByDeviceId.containsKey(id) &&
                  _settingsByDeviceId.containsKey(id));

          final transportEnum = widget.transport == 'wifi'
              ? SessionTransport.wifi
              : SessionTransport.ble;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              const Text(
                'Configure each device individually',
                style: TextStyle(
                  color: ThemeConstants.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),

              ...widget.deviceIds.map((deviceId) {
                final selectedProtocolId = _protocolIdByDeviceId[deviceId];
                final selectedProtocol = selectedProtocolId == null
                    ? null
                    : protocols.firstWhere(
                        (p) => p.id == selectedProtocolId,
                      );
                final settings = _settingsByDeviceId[deviceId];
                final showAdvanced = _showAdvancedByDeviceId[deviceId] ?? false;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ThemeConstants.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ThemeConstants.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _labelFor(deviceId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),

                      Text(
                        'Protocol',
                        style: TextStyle(
                          color: ThemeConstants.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),

                      DropdownButton<String>(
                        value: selectedProtocolId,
                        isExpanded: true,
                        hint: const Text('Select protocol'),
                        dropdownColor: ThemeConstants.surface,
                        items: protocols.map((p) {
                          return DropdownMenuItem<String>(
                            value: p.id,
                            child: Text(
                              p.templateName,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }).toList(),
                        onChanged: (newId) {
                          if (newId == null) return;
                          final p = protocols.firstWhere((x) => x.id == newId);
                          setState(() {
                            _protocolIdByDeviceId[deviceId] = newId;
                            _settingsByDeviceId[deviceId] =
                                _advancedDefaultsFromProtocol(p);
                            _activeDeviceId = deviceId;
                          });
                        },
                      ),

                      const SizedBox(height: 14),
                      // Advanced Settings collapsible header (same pattern as protocol detail).
                      if (selectedProtocol == null || settings == null) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'Select a protocol to edit advanced settings.',
                          style: TextStyle(color: ThemeConstants.textSecondary),
                        ),
                      ] else ...[
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showAdvancedByDeviceId[deviceId] = !showAdvanced;
                            });
                          },
                          child: Row(
                            children: [
                              const Icon(
                                Icons.settings_rounded,
                                color: ThemeConstants.accent,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Advanced Settings',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Icon(
                                showAdvanced
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: ThemeConstants.textSecondary,
                              ),
                            ],
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          child: !showAdvanced
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: _AdvancedSettingsPanel(
                                    protocolId: selectedProtocol.id,
                                    selectedDeviceIds: widget.deviceIds,
                                    settings: settings,
                                    delayedDeviceId: _delayedDeviceId,
                                    showSavePreset: _showSavePreset,
                                    onChangeSettings: (s) {
                                      setState(() =>
                                          _settingsByDeviceId[deviceId] = s);
                                    },
                                    onToggleSavePreset: () {
                                      setState(
                                          () => _showSavePreset = !_showSavePreset);
                                    },
                                    onChangeDelayedDeviceId: (id) {
                                      setState(() => _delayedDeviceId = id);
                                    },
                                  ),
                                ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),

              const SizedBox(height: 6),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _starting || !allSelected
                      ? null
                      : () async {
                          setState(() => _starting = true);
                          try {
                            final ctrl = ref.read(sessionEngineProvider.notifier);

                            final firstId = widget.deviceIds.first;
                            final firstProtocolId =
                                _protocolIdByDeviceId[firstId]!;
                            // IMPORTANT: resolve full protocol details before start.
                            // protocolList items can be lightweight; start payload needs
                            // full cycles/template fields (same as old flow).
                            final selectedProtocolIds =
                                _protocolIdByDeviceId.values.toSet();
                            final fullProtocolById = <String, Protocol>{};
                            await Future.wait(selectedProtocolIds.map((pid) async {
                              final detailed = await ref.read(
                                protocolDetailProvider(pid).future,
                              );
                              fullProtocolById[pid] = detailed;
                            }));

                            final commonProtocol = fullProtocolById[firstProtocolId]!;

                            final protocolByDevice = <String, Protocol>{};
                            for (final id in widget.deviceIds) {
                              final pid = _protocolIdByDeviceId[id]!;
                              protocolByDevice[id] = fullProtocolById[pid]!;
                            }

                            final advancedSettingsByDevice =
                                <String, AdvancedSettings>{};
                            for (final id in widget.deviceIds) {
                              advancedSettingsByDevice[id] = _settingsByDeviceId[id]!;
                            }

                            final commonAdvanced =
                                advancedSettingsByDevice[firstId]!;

                            ctrl.prepareSession(
                              deviceIds: widget.deviceIds,
                              transport: transportEnum,
                            );

                            ctrl.loadSession(
                              commonProtocol,
                              widget.deviceIds,
                              transport: transportEnum,
                              advancedSettings: commonAdvanced,
                              advancedSettingsByDevice: advancedSettingsByDevice,
                              delayedDeviceId: _delayedDeviceId,
                              protocolByDevice: protocolByDevice,
                              wifiConfigAlreadyPublished: false,
                            );

                            // Align timer UI close to “now”.
                            ctrl.applySessionClockOffsetFromWallAnchor(
                              DateTime.now(),
                            );

                            await ctrl.start();

                            if (!mounted) return;

                            context.push(
                              RoutePaths.session,
                              extra: {
                                'protocolId': commonProtocol.id,
                                'protocol': commonProtocol,
                                'deviceIds': widget.deviceIds,
                                'transport': widget.transport,
                                'advancedSettings': commonAdvanced,
                                'advancedSettingsByDevice': advancedSettingsByDevice,
                                'protocolByDeviceId': _protocolIdByDeviceId,
                                'delayedDeviceId': _delayedDeviceId,
                                'skipEngineBootstrap': true,
                              },
                            );
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Start failed: $e')),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _starting = false);
                          }
                        },
                  child: _starting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Start Session'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

final _presetsProvider = FutureProvider<List<Preset>>((ref) async {
  final repo = ref.read(presetRepositoryProvider);
  return repo.getPresets();
});

class _AdvancedSettingsPanel extends ConsumerWidget {
  final String protocolId;
  final List<String> selectedDeviceIds;
  final AdvancedSettings settings;
  final String? delayedDeviceId;
  final bool showSavePreset;
  final ValueChanged<AdvancedSettings> onChangeSettings;
  final VoidCallback onToggleSavePreset;
  final ValueChanged<String?> onChangeDelayedDeviceId;

  const _AdvancedSettingsPanel({
    required this.protocolId,
    required this.selectedDeviceIds,
    required this.settings,
    required this.delayedDeviceId,
    required this.showSavePreset,
    required this.onChangeSettings,
    required this.onToggleSavePreset,
    required this.onChangeDelayedDeviceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMulti = selectedDeviceIds.length >= 2;
    final presetsAsync = ref.watch(_presetsProvider);

    const vibMaxHz = 230.0;
    const vibMinHz = 0.0;

    Widget smallNumberSlider({
      required String label,
      required double value,
      required double min,
      required double max,
      required int divisions,
      required Color color,
      required ValueChanged<double> onChanged,
      String? unit,
    }) {
      final v = value.clamp(min, max);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: ThemeConstants.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '${v.toStringAsFixed(0)}${unit ?? ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          Slider(
            value: v,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: color,
            onChanged: onChanged,
          ),
        ],
      );
    }

    Widget toggle({
      required String label,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: ThemeConstants.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: ThemeConstants.accent,
              activeTrackColor: ThemeConstants.accent.withValues(alpha: 0.35),
              onChanged: onChanged,
            ),
          ],
        ),
      );
    }

    Widget slider({
      required String label,
      required int value,
      required Color valueColor,
      required ValueChanged<int> onChanged,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: ThemeConstants.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: 0,
            max: 11,
            divisions: 11,
            activeColor: valueColor,
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
      );
    }

    // NOTE: This mirrors the protocol detail advanced settings so per-device
    // behavior is identical.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'VIBRATION MODE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: ThemeConstants.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Off', 'Sweep', 'Single'].map((m) {
            final selected = settings.vibrationMode == m;
            return InkWell(
              onTap: () {
                if (m == 'Off') {
                  onChangeSettings(
                    settings.copyWith(
                      vibrationMode: 'Off',
                      vibMin: 0,
                      vibMax: 1,
                      vibrationSweepMin: 0,
                      vibrationSweepMax: 1,
                    ),
                  );
                  return;
                }
                onChangeSettings(settings.copyWith(vibrationMode: m));
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? ThemeConstants.accent.withValues(alpha: 0.18)
                      : ThemeConstants.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? ThemeConstants.accent : ThemeConstants.border,
                  ),
                ),
                child: Text(
                  m,
                  style: TextStyle(
                    color: selected ? ThemeConstants.accent : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 8),
        if (settings.vibrationMode == 'Sweep') ...[
          smallNumberSlider(
            label: 'Vibration Min (Hz)',
            value: settings.vibMin,
            min: vibMinHz,
            max: vibMaxHz - 1,
            divisions: (vibMaxHz - 1).toInt(),
            color: ThemeConstants.accent,
            unit: 'Hz',
            onChanged: (v) {
              var newMin = v;
              var newMax = settings.vibMax;
              if (newMin >= newMax) newMax = (newMin + 1).clamp(1, vibMaxHz);
              onChangeSettings(
                settings.copyWith(
                  vibMin: newMin,
                  vibMax: newMax,
                  vibrationSweepMin: newMin,
                  vibrationSweepMax: newMax,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          smallNumberSlider(
            label: 'Vibration Max (Hz)',
            value: settings.vibMax,
            min: vibMinHz + 1,
            max: vibMaxHz,
            divisions: (vibMaxHz - 1).toInt(),
            color: ThemeConstants.accent,
            unit: 'Hz',
            onChanged: (v) {
              var newMax = v;
              var newMin = settings.vibMin;
              if (newMax <= newMin) newMin = (newMax - 1).clamp(0, vibMaxHz - 1);
              onChangeSettings(
                settings.copyWith(
                  vibMin: newMin,
                  vibMax: newMax,
                  vibrationSweepMin: newMin,
                  vibrationSweepMax: newMax,
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 10),
        if (settings.vibrationMode == 'Single') ...[
          const Text(
            'FREQUENCY (HZ)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ThemeConstants.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey(
              'single_vibration_hz_${settings.vibrationSingleHz.toStringAsFixed(0)}',
            ),
            initialValue: settings.vibrationSingleHz.toStringAsFixed(0),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              hintText: 'Enter frequency (10-230)',
              hintStyle: const TextStyle(color: ThemeConstants.textTertiary),
              filled: true,
              fillColor: ThemeConstants.surfaceVariant,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              suffixText: 'Hz',
              suffixStyle: const TextStyle(
                color: ThemeConstants.textSecondary,
                fontWeight: FontWeight.w700,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: ThemeConstants.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: ThemeConstants.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: ThemeConstants.accent),
              ),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value) ?? 10;
              final clamped = parsed.clamp(10, 230).toDouble();
              if (clamped != settings.vibrationSingleHz) {
                onChangeSettings(
                  settings.copyWith(
                    vibrationSingleHz: clamped,
                    vibMin: clamped,
                    vibMax: clamped,
                    vibrationSweepMin: clamped,
                    vibrationSweepMax: clamped,
                  ),
                );
              }
            },
          ),
        ],

        const SizedBox(height: 8),
        if (settings.vibrationMode == 'Off') ...[
          const Text(
            'Vibration is Off.',
            style: TextStyle(color: ThemeConstants.textSecondary),
          ),
        ],

        const SizedBox(height: 10),

        // Hot / Cold intensity — match protocol detail.
        slider(
          label: 'Hot Pad Intensity',
          value: settings.hotLevel,
          valueColor: const Color(0xFFE09060),
          onChanged: (v) =>
              onChangeSettings(settings.copyWith(hotLevel: v, hotPack: true)),
        ),
        const SizedBox(height: 8),
        slider(
          label: 'Cold Pad Intensity',
          value: settings.coldLevel,
          valueColor: Colors.blueAccent,
          onChanged: (v) =>
              onChangeSettings(settings.copyWith(coldLevel: v, coldPack: true)),
        ),

        const SizedBox(height: 10),
        const Text(
          'Start Delay (seconds)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: ThemeConstants.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey('start_delay_${settings.startDelay}'),
          initialValue: settings.startDelay.toString(),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: 'Enter seconds (0-60)',
            hintStyle: const TextStyle(color: ThemeConstants.textTertiary),
            filled: true,
            fillColor: ThemeConstants.surfaceVariant,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            suffixText: 'sec',
            suffixStyle: const TextStyle(
              color: ThemeConstants.textSecondary,
              fontWeight: FontWeight.w700,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: ThemeConstants.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: ThemeConstants.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: ThemeConstants.accent),
            ),
          ),
          onChanged: (value) {
            final parsed = int.tryParse(value) ?? 0;
            final clamped = parsed.clamp(0, 60);
            if (clamped != settings.startDelay) {
              onChangeSettings(settings.copyWith(startDelay: clamped));
            }
          },
        ),

        if (isMulti && settings.startDelay > 0) ...[
          const SizedBox(height: 6),
          const Text(
            'Delay which device?',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ThemeConstants.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedDeviceIds.map((id) {
              final selected = delayedDeviceId == id;
              return InkWell(
                onTap: () => onChangeDelayedDeviceId(id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? ThemeConstants.accent.withValues(alpha: 0.18)
                        : ThemeConstants.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          selected ? ThemeConstants.accent : ThemeConstants.border,
                    ),
                  ),
                  child: Text(
                    id,
                    style: TextStyle(
                      color: selected
                          ? ThemeConstants.accent
                          : ThemeConstants.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],

        const SizedBox(height: 10),
        // Cycle 1 / 5 / LED / Flip in compact 2-column grid
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.6,
          ),
          children: [
            toggle(
              label: 'Cycle 1 Initialization',
              value: settings.cycle1Initiation,
              onChanged: (v) =>
                  onChangeSettings(settings.copyWith(cycle1Initiation: v)),
            ),
            toggle(
              label: 'Cycle 5 Completion',
              value: settings.cycle5Completion,
              onChanged: (v) =>
                  onChangeSettings(settings.copyWith(cycle5Completion: v)),
            ),
            toggle(
              label: 'LED',
              value: settings.lights,
              onChanged: (v) => onChangeSettings(settings.copyWith(lights: v)),
            ),
            toggle(
              label: 'Flip Pad',
              value: settings.flipSettings,
              onChanged: (v) =>
                  onChangeSettings(settings.copyWith(flipSettings: v)),
            ),
          ],
        ),

        const SizedBox(height: 10),
        InkWell(
          onTap: onToggleSavePreset,
          child: Row(
            children: [
              const Icon(Icons.save_rounded,
                  size: 16, color: ThemeConstants.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Save configuration as preset',
                style: TextStyle(
                  color: ThemeConstants.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),

        if (showSavePreset) ...[
          const SizedBox(height: 10),
          presetsAsync.when(
            data: (presets) {
              presets.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
              Future<void> saveToSlot(int idx) async {
                final repo = ref.read(presetRepositoryProvider);
                final name = 'Preset ${idx + 1}';
                if (idx < presets.length) {
                  await repo.updatePreset(
                    id: presets[idx].id,
                    name: name,
                    deviceIds: selectedDeviceIds,
                    protocolId: protocolId,
                    advancedSettings: settings,
                  );
                } else {
                  await repo.createPreset(
                    name: name,
                    deviceIds: selectedDeviceIds,
                    protocolId: protocolId,
                    advancedSettings: settings,
                  );
                }
              }
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ThemeConstants.border),
                ),
                child: Row(
                  children: List.generate(3, (i) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
                        child: OutlinedButton(
                          onPressed: selectedDeviceIds.isEmpty ? null : () => saveToSlot(i),
                          child: Text('Slot ${i + 1}'),
                        ),
                      ),
                    );
                  }),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: HwLoading(),
            ),
            error: (e, _) => Text(
              'Failed to load presets: $e',
              style: const TextStyle(color: ThemeConstants.error, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}

