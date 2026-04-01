// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
class $PairedDevicesTable extends PairedDevices
    with TableInfo<$PairedDevicesTable, PairedDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PairedDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _macAddressMeta =
      const VerificationMeta('macAddress');
  @override
  late final GeneratedColumn<String> macAddress = GeneratedColumn<String>(
      'mac_address', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _autoReconnectMeta =
      const VerificationMeta('autoReconnect');
  @override
  late final GeneratedColumn<bool> autoReconnect = GeneratedColumn<bool>(
      'auto_reconnect', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("auto_reconnect" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _lastConnectedMeta =
      const VerificationMeta('lastConnected');
  @override
  late final GeneratedColumn<DateTime> lastConnected =
      GeneratedColumn<DateTime>('last_connected', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, macAddress, name, autoReconnect, lastConnected, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'paired_devices';
  @override
  VerificationContext validateIntegrity(Insertable<PairedDevice> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('mac_address')) {
      context.handle(
          _macAddressMeta,
          macAddress.isAcceptableOrUnknown(
              data['mac_address']!, _macAddressMeta));
    } else if (isInserting) {
      context.missing(_macAddressMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('auto_reconnect')) {
      context.handle(
          _autoReconnectMeta,
          autoReconnect.isAcceptableOrUnknown(
              data['auto_reconnect']!, _autoReconnectMeta));
    }
    if (data.containsKey('last_connected')) {
      context.handle(
          _lastConnectedMeta,
          lastConnected.isAcceptableOrUnknown(
              data['last_connected']!, _lastConnectedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PairedDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PairedDevice(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      macAddress: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mac_address'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      autoReconnect: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}auto_reconnect'])!,
      lastConnected: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_connected']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $PairedDevicesTable createAlias(String alias) {
    return $PairedDevicesTable(attachedDatabase, alias);
  }
}

class PairedDevice extends DataClass implements Insertable<PairedDevice> {
  final String id;
  final String macAddress;
  final String name;
  final bool autoReconnect;
  final DateTime? lastConnected;
  final DateTime createdAt;
  const PairedDevice(
      {required this.id,
      required this.macAddress,
      required this.name,
      required this.autoReconnect,
      this.lastConnected,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['mac_address'] = Variable<String>(macAddress);
    map['name'] = Variable<String>(name);
    map['auto_reconnect'] = Variable<bool>(autoReconnect);
    if (!nullToAbsent || lastConnected != null) {
      map['last_connected'] = Variable<DateTime>(lastConnected);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PairedDevicesCompanion toCompanion(bool nullToAbsent) {
    return PairedDevicesCompanion(
      id: Value(id),
      macAddress: Value(macAddress),
      name: Value(name),
      autoReconnect: Value(autoReconnect),
      lastConnected: lastConnected == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConnected),
      createdAt: Value(createdAt),
    );
  }

  factory PairedDevice.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PairedDevice(
      id: serializer.fromJson<String>(json['id']),
      macAddress: serializer.fromJson<String>(json['macAddress']),
      name: serializer.fromJson<String>(json['name']),
      autoReconnect: serializer.fromJson<bool>(json['autoReconnect']),
      lastConnected: serializer.fromJson<DateTime?>(json['lastConnected']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'macAddress': serializer.toJson<String>(macAddress),
      'name': serializer.toJson<String>(name),
      'autoReconnect': serializer.toJson<bool>(autoReconnect),
      'lastConnected': serializer.toJson<DateTime?>(lastConnected),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PairedDevice copyWith(
          {String? id,
          String? macAddress,
          String? name,
          bool? autoReconnect,
          Value<DateTime?> lastConnected = const Value.absent(),
          DateTime? createdAt}) =>
      PairedDevice(
        id: id ?? this.id,
        macAddress: macAddress ?? this.macAddress,
        name: name ?? this.name,
        autoReconnect: autoReconnect ?? this.autoReconnect,
        lastConnected:
            lastConnected.present ? lastConnected.value : this.lastConnected,
        createdAt: createdAt ?? this.createdAt,
      );
  PairedDevice copyWithCompanion(PairedDevicesCompanion data) {
    return PairedDevice(
      id: data.id.present ? data.id.value : this.id,
      macAddress:
          data.macAddress.present ? data.macAddress.value : this.macAddress,
      name: data.name.present ? data.name.value : this.name,
      autoReconnect: data.autoReconnect.present
          ? data.autoReconnect.value
          : this.autoReconnect,
      lastConnected: data.lastConnected.present
          ? data.lastConnected.value
          : this.lastConnected,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PairedDevice(')
          ..write('id: $id, ')
          ..write('macAddress: $macAddress, ')
          ..write('name: $name, ')
          ..write('autoReconnect: $autoReconnect, ')
          ..write('lastConnected: $lastConnected, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, macAddress, name, autoReconnect, lastConnected, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PairedDevice &&
          other.id == this.id &&
          other.macAddress == this.macAddress &&
          other.name == this.name &&
          other.autoReconnect == this.autoReconnect &&
          other.lastConnected == this.lastConnected &&
          other.createdAt == this.createdAt);
}

class PairedDevicesCompanion extends UpdateCompanion<PairedDevice> {
  final Value<String> id;
  final Value<String> macAddress;
  final Value<String> name;
  final Value<bool> autoReconnect;
  final Value<DateTime?> lastConnected;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PairedDevicesCompanion({
    this.id = const Value.absent(),
    this.macAddress = const Value.absent(),
    this.name = const Value.absent(),
    this.autoReconnect = const Value.absent(),
    this.lastConnected = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PairedDevicesCompanion.insert({
    required String id,
    required String macAddress,
    required String name,
    this.autoReconnect = const Value.absent(),
    this.lastConnected = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        macAddress = Value(macAddress),
        name = Value(name);
  static Insertable<PairedDevice> custom({
    Expression<String>? id,
    Expression<String>? macAddress,
    Expression<String>? name,
    Expression<bool>? autoReconnect,
    Expression<DateTime>? lastConnected,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (macAddress != null) 'mac_address': macAddress,
      if (name != null) 'name': name,
      if (autoReconnect != null) 'auto_reconnect': autoReconnect,
      if (lastConnected != null) 'last_connected': lastConnected,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PairedDevicesCompanion copyWith(
      {Value<String>? id,
      Value<String>? macAddress,
      Value<String>? name,
      Value<bool>? autoReconnect,
      Value<DateTime?>? lastConnected,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return PairedDevicesCompanion(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      name: name ?? this.name,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      lastConnected: lastConnected ?? this.lastConnected,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (macAddress.present) {
      map['mac_address'] = Variable<String>(macAddress.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (autoReconnect.present) {
      map['auto_reconnect'] = Variable<bool>(autoReconnect.value);
    }
    if (lastConnected.present) {
      map['last_connected'] = Variable<DateTime>(lastConnected.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PairedDevicesCompanion(')
          ..write('id: $id, ')
          ..write('macAddress: $macAddress, ')
          ..write('name: $name, ')
          ..write('autoReconnect: $autoReconnect, ')
          ..write('lastConnected: $lastConnected, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedProtocolsTable extends CachedProtocols
    with TableInfo<$CachedProtocolsTable, CachedProtocol> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProtocolsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _templateNameMeta =
      const VerificationMeta('templateName');
  @override
  late final GeneratedColumn<String> templateName = GeneratedColumn<String>(
      'template_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sessionsMeta =
      const VerificationMeta('sessions');
  @override
  late final GeneratedColumn<int> sessions = GeneratedColumn<int>(
      'sessions', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _cyclesJsonMeta =
      const VerificationMeta('cyclesJson');
  @override
  late final GeneratedColumn<String> cyclesJson = GeneratedColumn<String>(
      'cycles_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _hotdropMeta =
      const VerificationMeta('hotdrop');
  @override
  late final GeneratedColumn<double> hotdrop = GeneratedColumn<double>(
      'hotdrop', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _colddropMeta =
      const VerificationMeta('colddrop');
  @override
  late final GeneratedColumn<double> colddrop = GeneratedColumn<double>(
      'colddrop', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _vibminMeta = const VerificationMeta('vibmin');
  @override
  late final GeneratedColumn<double> vibmin = GeneratedColumn<double>(
      'vibmin', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _vibmaxMeta = const VerificationMeta('vibmax');
  @override
  late final GeneratedColumn<double> vibmax = GeneratedColumn<double>(
      'vibmax', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _cycle1Meta = const VerificationMeta('cycle1');
  @override
  late final GeneratedColumn<bool> cycle1 = GeneratedColumn<bool>(
      'cycle1', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("cycle1" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _cycle5Meta = const VerificationMeta('cycle5');
  @override
  late final GeneratedColumn<bool> cycle5 = GeneratedColumn<bool>(
      'cycle5', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("cycle5" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _edgecycledurationMeta =
      const VerificationMeta('edgecycleduration');
  @override
  late final GeneratedColumn<double> edgecycleduration =
      GeneratedColumn<double>('edgecycleduration', aliasedName, false,
          type: DriftSqlType.double,
          requiredDuringInsert: false,
          defaultValue: const Constant(0.0));
  static const VerificationMeta _sessionPauseMeta =
      const VerificationMeta('sessionPause');
  @override
  late final GeneratedColumn<double> sessionPause = GeneratedColumn<double>(
      'session_pause', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        templateName,
        sessions,
        cyclesJson,
        hotdrop,
        colddrop,
        vibmin,
        vibmax,
        cycle1,
        cycle5,
        edgecycleduration,
        sessionPause,
        description,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_protocols';
  @override
  VerificationContext validateIntegrity(Insertable<CachedProtocol> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('template_name')) {
      context.handle(
          _templateNameMeta,
          templateName.isAcceptableOrUnknown(
              data['template_name']!, _templateNameMeta));
    } else if (isInserting) {
      context.missing(_templateNameMeta);
    }
    if (data.containsKey('sessions')) {
      context.handle(_sessionsMeta,
          sessions.isAcceptableOrUnknown(data['sessions']!, _sessionsMeta));
    }
    if (data.containsKey('cycles_json')) {
      context.handle(
          _cyclesJsonMeta,
          cyclesJson.isAcceptableOrUnknown(
              data['cycles_json']!, _cyclesJsonMeta));
    } else if (isInserting) {
      context.missing(_cyclesJsonMeta);
    }
    if (data.containsKey('hotdrop')) {
      context.handle(_hotdropMeta,
          hotdrop.isAcceptableOrUnknown(data['hotdrop']!, _hotdropMeta));
    }
    if (data.containsKey('colddrop')) {
      context.handle(_colddropMeta,
          colddrop.isAcceptableOrUnknown(data['colddrop']!, _colddropMeta));
    }
    if (data.containsKey('vibmin')) {
      context.handle(_vibminMeta,
          vibmin.isAcceptableOrUnknown(data['vibmin']!, _vibminMeta));
    }
    if (data.containsKey('vibmax')) {
      context.handle(_vibmaxMeta,
          vibmax.isAcceptableOrUnknown(data['vibmax']!, _vibmaxMeta));
    }
    if (data.containsKey('cycle1')) {
      context.handle(_cycle1Meta,
          cycle1.isAcceptableOrUnknown(data['cycle1']!, _cycle1Meta));
    }
    if (data.containsKey('cycle5')) {
      context.handle(_cycle5Meta,
          cycle5.isAcceptableOrUnknown(data['cycle5']!, _cycle5Meta));
    }
    if (data.containsKey('edgecycleduration')) {
      context.handle(
          _edgecycledurationMeta,
          edgecycleduration.isAcceptableOrUnknown(
              data['edgecycleduration']!, _edgecycledurationMeta));
    }
    if (data.containsKey('session_pause')) {
      context.handle(
          _sessionPauseMeta,
          sessionPause.isAcceptableOrUnknown(
              data['session_pause']!, _sessionPauseMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedProtocol map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProtocol(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      templateName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}template_name'])!,
      sessions: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sessions'])!,
      cyclesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cycles_json'])!,
      hotdrop: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}hotdrop'])!,
      colddrop: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}colddrop'])!,
      vibmin: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}vibmin'])!,
      vibmax: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}vibmax'])!,
      cycle1: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}cycle1'])!,
      cycle5: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}cycle5'])!,
      edgecycleduration: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}edgecycleduration'])!,
      sessionPause: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}session_pause'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedProtocolsTable createAlias(String alias) {
    return $CachedProtocolsTable(attachedDatabase, alias);
  }
}

class CachedProtocol extends DataClass implements Insertable<CachedProtocol> {
  final String id;
  final String templateName;
  final int sessions;
  final String cyclesJson;
  final double hotdrop;
  final double colddrop;
  final double vibmin;
  final double vibmax;
  final bool cycle1;
  final bool cycle5;
  final double edgecycleduration;
  final double sessionPause;
  final String description;
  final DateTime cachedAt;
  const CachedProtocol(
      {required this.id,
      required this.templateName,
      required this.sessions,
      required this.cyclesJson,
      required this.hotdrop,
      required this.colddrop,
      required this.vibmin,
      required this.vibmax,
      required this.cycle1,
      required this.cycle5,
      required this.edgecycleduration,
      required this.sessionPause,
      required this.description,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['template_name'] = Variable<String>(templateName);
    map['sessions'] = Variable<int>(sessions);
    map['cycles_json'] = Variable<String>(cyclesJson);
    map['hotdrop'] = Variable<double>(hotdrop);
    map['colddrop'] = Variable<double>(colddrop);
    map['vibmin'] = Variable<double>(vibmin);
    map['vibmax'] = Variable<double>(vibmax);
    map['cycle1'] = Variable<bool>(cycle1);
    map['cycle5'] = Variable<bool>(cycle5);
    map['edgecycleduration'] = Variable<double>(edgecycleduration);
    map['session_pause'] = Variable<double>(sessionPause);
    map['description'] = Variable<String>(description);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedProtocolsCompanion toCompanion(bool nullToAbsent) {
    return CachedProtocolsCompanion(
      id: Value(id),
      templateName: Value(templateName),
      sessions: Value(sessions),
      cyclesJson: Value(cyclesJson),
      hotdrop: Value(hotdrop),
      colddrop: Value(colddrop),
      vibmin: Value(vibmin),
      vibmax: Value(vibmax),
      cycle1: Value(cycle1),
      cycle5: Value(cycle5),
      edgecycleduration: Value(edgecycleduration),
      sessionPause: Value(sessionPause),
      description: Value(description),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedProtocol.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProtocol(
      id: serializer.fromJson<String>(json['id']),
      templateName: serializer.fromJson<String>(json['templateName']),
      sessions: serializer.fromJson<int>(json['sessions']),
      cyclesJson: serializer.fromJson<String>(json['cyclesJson']),
      hotdrop: serializer.fromJson<double>(json['hotdrop']),
      colddrop: serializer.fromJson<double>(json['colddrop']),
      vibmin: serializer.fromJson<double>(json['vibmin']),
      vibmax: serializer.fromJson<double>(json['vibmax']),
      cycle1: serializer.fromJson<bool>(json['cycle1']),
      cycle5: serializer.fromJson<bool>(json['cycle5']),
      edgecycleduration: serializer.fromJson<double>(json['edgecycleduration']),
      sessionPause: serializer.fromJson<double>(json['sessionPause']),
      description: serializer.fromJson<String>(json['description']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'templateName': serializer.toJson<String>(templateName),
      'sessions': serializer.toJson<int>(sessions),
      'cyclesJson': serializer.toJson<String>(cyclesJson),
      'hotdrop': serializer.toJson<double>(hotdrop),
      'colddrop': serializer.toJson<double>(colddrop),
      'vibmin': serializer.toJson<double>(vibmin),
      'vibmax': serializer.toJson<double>(vibmax),
      'cycle1': serializer.toJson<bool>(cycle1),
      'cycle5': serializer.toJson<bool>(cycle5),
      'edgecycleduration': serializer.toJson<double>(edgecycleduration),
      'sessionPause': serializer.toJson<double>(sessionPause),
      'description': serializer.toJson<String>(description),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedProtocol copyWith(
          {String? id,
          String? templateName,
          int? sessions,
          String? cyclesJson,
          double? hotdrop,
          double? colddrop,
          double? vibmin,
          double? vibmax,
          bool? cycle1,
          bool? cycle5,
          double? edgecycleduration,
          double? sessionPause,
          String? description,
          DateTime? cachedAt}) =>
      CachedProtocol(
        id: id ?? this.id,
        templateName: templateName ?? this.templateName,
        sessions: sessions ?? this.sessions,
        cyclesJson: cyclesJson ?? this.cyclesJson,
        hotdrop: hotdrop ?? this.hotdrop,
        colddrop: colddrop ?? this.colddrop,
        vibmin: vibmin ?? this.vibmin,
        vibmax: vibmax ?? this.vibmax,
        cycle1: cycle1 ?? this.cycle1,
        cycle5: cycle5 ?? this.cycle5,
        edgecycleduration: edgecycleduration ?? this.edgecycleduration,
        sessionPause: sessionPause ?? this.sessionPause,
        description: description ?? this.description,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedProtocol copyWithCompanion(CachedProtocolsCompanion data) {
    return CachedProtocol(
      id: data.id.present ? data.id.value : this.id,
      templateName: data.templateName.present
          ? data.templateName.value
          : this.templateName,
      sessions: data.sessions.present ? data.sessions.value : this.sessions,
      cyclesJson:
          data.cyclesJson.present ? data.cyclesJson.value : this.cyclesJson,
      hotdrop: data.hotdrop.present ? data.hotdrop.value : this.hotdrop,
      colddrop: data.colddrop.present ? data.colddrop.value : this.colddrop,
      vibmin: data.vibmin.present ? data.vibmin.value : this.vibmin,
      vibmax: data.vibmax.present ? data.vibmax.value : this.vibmax,
      cycle1: data.cycle1.present ? data.cycle1.value : this.cycle1,
      cycle5: data.cycle5.present ? data.cycle5.value : this.cycle5,
      edgecycleduration: data.edgecycleduration.present
          ? data.edgecycleduration.value
          : this.edgecycleduration,
      sessionPause: data.sessionPause.present
          ? data.sessionPause.value
          : this.sessionPause,
      description:
          data.description.present ? data.description.value : this.description,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProtocol(')
          ..write('id: $id, ')
          ..write('templateName: $templateName, ')
          ..write('sessions: $sessions, ')
          ..write('cyclesJson: $cyclesJson, ')
          ..write('hotdrop: $hotdrop, ')
          ..write('colddrop: $colddrop, ')
          ..write('vibmin: $vibmin, ')
          ..write('vibmax: $vibmax, ')
          ..write('cycle1: $cycle1, ')
          ..write('cycle5: $cycle5, ')
          ..write('edgecycleduration: $edgecycleduration, ')
          ..write('sessionPause: $sessionPause, ')
          ..write('description: $description, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      templateName,
      sessions,
      cyclesJson,
      hotdrop,
      colddrop,
      vibmin,
      vibmax,
      cycle1,
      cycle5,
      edgecycleduration,
      sessionPause,
      description,
      cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProtocol &&
          other.id == this.id &&
          other.templateName == this.templateName &&
          other.sessions == this.sessions &&
          other.cyclesJson == this.cyclesJson &&
          other.hotdrop == this.hotdrop &&
          other.colddrop == this.colddrop &&
          other.vibmin == this.vibmin &&
          other.vibmax == this.vibmax &&
          other.cycle1 == this.cycle1 &&
          other.cycle5 == this.cycle5 &&
          other.edgecycleduration == this.edgecycleduration &&
          other.sessionPause == this.sessionPause &&
          other.description == this.description &&
          other.cachedAt == this.cachedAt);
}

class CachedProtocolsCompanion extends UpdateCompanion<CachedProtocol> {
  final Value<String> id;
  final Value<String> templateName;
  final Value<int> sessions;
  final Value<String> cyclesJson;
  final Value<double> hotdrop;
  final Value<double> colddrop;
  final Value<double> vibmin;
  final Value<double> vibmax;
  final Value<bool> cycle1;
  final Value<bool> cycle5;
  final Value<double> edgecycleduration;
  final Value<double> sessionPause;
  final Value<String> description;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedProtocolsCompanion({
    this.id = const Value.absent(),
    this.templateName = const Value.absent(),
    this.sessions = const Value.absent(),
    this.cyclesJson = const Value.absent(),
    this.hotdrop = const Value.absent(),
    this.colddrop = const Value.absent(),
    this.vibmin = const Value.absent(),
    this.vibmax = const Value.absent(),
    this.cycle1 = const Value.absent(),
    this.cycle5 = const Value.absent(),
    this.edgecycleduration = const Value.absent(),
    this.sessionPause = const Value.absent(),
    this.description = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProtocolsCompanion.insert({
    required String id,
    required String templateName,
    this.sessions = const Value.absent(),
    required String cyclesJson,
    this.hotdrop = const Value.absent(),
    this.colddrop = const Value.absent(),
    this.vibmin = const Value.absent(),
    this.vibmax = const Value.absent(),
    this.cycle1 = const Value.absent(),
    this.cycle5 = const Value.absent(),
    this.edgecycleduration = const Value.absent(),
    this.sessionPause = const Value.absent(),
    this.description = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        templateName = Value(templateName),
        cyclesJson = Value(cyclesJson);
  static Insertable<CachedProtocol> custom({
    Expression<String>? id,
    Expression<String>? templateName,
    Expression<int>? sessions,
    Expression<String>? cyclesJson,
    Expression<double>? hotdrop,
    Expression<double>? colddrop,
    Expression<double>? vibmin,
    Expression<double>? vibmax,
    Expression<bool>? cycle1,
    Expression<bool>? cycle5,
    Expression<double>? edgecycleduration,
    Expression<double>? sessionPause,
    Expression<String>? description,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (templateName != null) 'template_name': templateName,
      if (sessions != null) 'sessions': sessions,
      if (cyclesJson != null) 'cycles_json': cyclesJson,
      if (hotdrop != null) 'hotdrop': hotdrop,
      if (colddrop != null) 'colddrop': colddrop,
      if (vibmin != null) 'vibmin': vibmin,
      if (vibmax != null) 'vibmax': vibmax,
      if (cycle1 != null) 'cycle1': cycle1,
      if (cycle5 != null) 'cycle5': cycle5,
      if (edgecycleduration != null) 'edgecycleduration': edgecycleduration,
      if (sessionPause != null) 'session_pause': sessionPause,
      if (description != null) 'description': description,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProtocolsCompanion copyWith(
      {Value<String>? id,
      Value<String>? templateName,
      Value<int>? sessions,
      Value<String>? cyclesJson,
      Value<double>? hotdrop,
      Value<double>? colddrop,
      Value<double>? vibmin,
      Value<double>? vibmax,
      Value<bool>? cycle1,
      Value<bool>? cycle5,
      Value<double>? edgecycleduration,
      Value<double>? sessionPause,
      Value<String>? description,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return CachedProtocolsCompanion(
      id: id ?? this.id,
      templateName: templateName ?? this.templateName,
      sessions: sessions ?? this.sessions,
      cyclesJson: cyclesJson ?? this.cyclesJson,
      hotdrop: hotdrop ?? this.hotdrop,
      colddrop: colddrop ?? this.colddrop,
      vibmin: vibmin ?? this.vibmin,
      vibmax: vibmax ?? this.vibmax,
      cycle1: cycle1 ?? this.cycle1,
      cycle5: cycle5 ?? this.cycle5,
      edgecycleduration: edgecycleduration ?? this.edgecycleduration,
      sessionPause: sessionPause ?? this.sessionPause,
      description: description ?? this.description,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (templateName.present) {
      map['template_name'] = Variable<String>(templateName.value);
    }
    if (sessions.present) {
      map['sessions'] = Variable<int>(sessions.value);
    }
    if (cyclesJson.present) {
      map['cycles_json'] = Variable<String>(cyclesJson.value);
    }
    if (hotdrop.present) {
      map['hotdrop'] = Variable<double>(hotdrop.value);
    }
    if (colddrop.present) {
      map['colddrop'] = Variable<double>(colddrop.value);
    }
    if (vibmin.present) {
      map['vibmin'] = Variable<double>(vibmin.value);
    }
    if (vibmax.present) {
      map['vibmax'] = Variable<double>(vibmax.value);
    }
    if (cycle1.present) {
      map['cycle1'] = Variable<bool>(cycle1.value);
    }
    if (cycle5.present) {
      map['cycle5'] = Variable<bool>(cycle5.value);
    }
    if (edgecycleduration.present) {
      map['edgecycleduration'] = Variable<double>(edgecycleduration.value);
    }
    if (sessionPause.present) {
      map['session_pause'] = Variable<double>(sessionPause.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProtocolsCompanion(')
          ..write('id: $id, ')
          ..write('templateName: $templateName, ')
          ..write('sessions: $sessions, ')
          ..write('cyclesJson: $cyclesJson, ')
          ..write('hotdrop: $hotdrop, ')
          ..write('colddrop: $colddrop, ')
          ..write('vibmin: $vibmin, ')
          ..write('vibmax: $vibmax, ')
          ..write('cycle1: $cycle1, ')
          ..write('cycle5: $cycle5, ')
          ..write('edgecycleduration: $edgecycleduration, ')
          ..write('sessionPause: $sessionPause, ')
          ..write('description: $description, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSessionsTable extends LocalSessions
    with TableInfo<$LocalSessionsTable, LocalSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _protocolIdMeta =
      const VerificationMeta('protocolId');
  @override
  late final GeneratedColumn<String> protocolId = GeneratedColumn<String>(
      'protocol_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _protocolNameMeta =
      const VerificationMeta('protocolName');
  @override
  late final GeneratedColumn<String> protocolName = GeneratedColumn<String>(
      'protocol_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deviceIdsMeta =
      const VerificationMeta('deviceIds');
  @override
  late final GeneratedColumn<String> deviceIds = GeneratedColumn<String>(
      'device_ids', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _durationSecondsMeta =
      const VerificationMeta('durationSeconds');
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
      'duration_seconds', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _elapsedSecondsMeta =
      const VerificationMeta('elapsedSeconds');
  @override
  late final GeneratedColumn<int> elapsedSeconds = GeneratedColumn<int>(
      'elapsed_seconds', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _discomfortBeforeMeta =
      const VerificationMeta('discomfortBefore');
  @override
  late final GeneratedColumn<int> discomfortBefore = GeneratedColumn<int>(
      'discomfort_before', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _discomfortAfterMeta =
      const VerificationMeta('discomfortAfter');
  @override
  late final GeneratedColumn<int> discomfortAfter = GeneratedColumn<int>(
      'discomfort_after', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
      'synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("synced" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
      'completed_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        protocolId,
        protocolName,
        deviceIds,
        durationSeconds,
        elapsedSeconds,
        discomfortBefore,
        discomfortAfter,
        notes,
        synced,
        completedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sessions';
  @override
  VerificationContext validateIntegrity(Insertable<LocalSession> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('protocol_id')) {
      context.handle(
          _protocolIdMeta,
          protocolId.isAcceptableOrUnknown(
              data['protocol_id']!, _protocolIdMeta));
    } else if (isInserting) {
      context.missing(_protocolIdMeta);
    }
    if (data.containsKey('protocol_name')) {
      context.handle(
          _protocolNameMeta,
          protocolName.isAcceptableOrUnknown(
              data['protocol_name']!, _protocolNameMeta));
    } else if (isInserting) {
      context.missing(_protocolNameMeta);
    }
    if (data.containsKey('device_ids')) {
      context.handle(_deviceIdsMeta,
          deviceIds.isAcceptableOrUnknown(data['device_ids']!, _deviceIdsMeta));
    } else if (isInserting) {
      context.missing(_deviceIdsMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
          _durationSecondsMeta,
          durationSeconds.isAcceptableOrUnknown(
              data['duration_seconds']!, _durationSecondsMeta));
    } else if (isInserting) {
      context.missing(_durationSecondsMeta);
    }
    if (data.containsKey('elapsed_seconds')) {
      context.handle(
          _elapsedSecondsMeta,
          elapsedSeconds.isAcceptableOrUnknown(
              data['elapsed_seconds']!, _elapsedSecondsMeta));
    } else if (isInserting) {
      context.missing(_elapsedSecondsMeta);
    }
    if (data.containsKey('discomfort_before')) {
      context.handle(
          _discomfortBeforeMeta,
          discomfortBefore.isAcceptableOrUnknown(
              data['discomfort_before']!, _discomfortBeforeMeta));
    }
    if (data.containsKey('discomfort_after')) {
      context.handle(
          _discomfortAfterMeta,
          discomfortAfter.isAcceptableOrUnknown(
              data['discomfort_after']!, _discomfortAfterMeta));
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('synced')) {
      context.handle(_syncedMeta,
          synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta));
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSession(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      protocolId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}protocol_id'])!,
      protocolName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}protocol_name'])!,
      deviceIds: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_ids'])!,
      durationSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_seconds'])!,
      elapsedSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}elapsed_seconds'])!,
      discomfortBefore: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}discomfort_before']),
      discomfortAfter: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}discomfort_after']),
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      synced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}synced'])!,
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}completed_at'])!,
    );
  }

  @override
  $LocalSessionsTable createAlias(String alias) {
    return $LocalSessionsTable(attachedDatabase, alias);
  }
}

class LocalSession extends DataClass implements Insertable<LocalSession> {
  final String id;
  final String protocolId;
  final String protocolName;
  final String deviceIds;
  final int durationSeconds;
  final int elapsedSeconds;
  final int? discomfortBefore;
  final int? discomfortAfter;
  final String? notes;
  final bool synced;
  final DateTime completedAt;
  const LocalSession(
      {required this.id,
      required this.protocolId,
      required this.protocolName,
      required this.deviceIds,
      required this.durationSeconds,
      required this.elapsedSeconds,
      this.discomfortBefore,
      this.discomfortAfter,
      this.notes,
      required this.synced,
      required this.completedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['protocol_id'] = Variable<String>(protocolId);
    map['protocol_name'] = Variable<String>(protocolName);
    map['device_ids'] = Variable<String>(deviceIds);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['elapsed_seconds'] = Variable<int>(elapsedSeconds);
    if (!nullToAbsent || discomfortBefore != null) {
      map['discomfort_before'] = Variable<int>(discomfortBefore);
    }
    if (!nullToAbsent || discomfortAfter != null) {
      map['discomfort_after'] = Variable<int>(discomfortAfter);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['synced'] = Variable<bool>(synced);
    map['completed_at'] = Variable<DateTime>(completedAt);
    return map;
  }

  LocalSessionsCompanion toCompanion(bool nullToAbsent) {
    return LocalSessionsCompanion(
      id: Value(id),
      protocolId: Value(protocolId),
      protocolName: Value(protocolName),
      deviceIds: Value(deviceIds),
      durationSeconds: Value(durationSeconds),
      elapsedSeconds: Value(elapsedSeconds),
      discomfortBefore: discomfortBefore == null && nullToAbsent
          ? const Value.absent()
          : Value(discomfortBefore),
      discomfortAfter: discomfortAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(discomfortAfter),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      synced: Value(synced),
      completedAt: Value(completedAt),
    );
  }

  factory LocalSession.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSession(
      id: serializer.fromJson<String>(json['id']),
      protocolId: serializer.fromJson<String>(json['protocolId']),
      protocolName: serializer.fromJson<String>(json['protocolName']),
      deviceIds: serializer.fromJson<String>(json['deviceIds']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      elapsedSeconds: serializer.fromJson<int>(json['elapsedSeconds']),
      discomfortBefore: serializer.fromJson<int?>(json['discomfortBefore']),
      discomfortAfter: serializer.fromJson<int?>(json['discomfortAfter']),
      notes: serializer.fromJson<String?>(json['notes']),
      synced: serializer.fromJson<bool>(json['synced']),
      completedAt: serializer.fromJson<DateTime>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'protocolId': serializer.toJson<String>(protocolId),
      'protocolName': serializer.toJson<String>(protocolName),
      'deviceIds': serializer.toJson<String>(deviceIds),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'elapsedSeconds': serializer.toJson<int>(elapsedSeconds),
      'discomfortBefore': serializer.toJson<int?>(discomfortBefore),
      'discomfortAfter': serializer.toJson<int?>(discomfortAfter),
      'notes': serializer.toJson<String?>(notes),
      'synced': serializer.toJson<bool>(synced),
      'completedAt': serializer.toJson<DateTime>(completedAt),
    };
  }

  LocalSession copyWith(
          {String? id,
          String? protocolId,
          String? protocolName,
          String? deviceIds,
          int? durationSeconds,
          int? elapsedSeconds,
          Value<int?> discomfortBefore = const Value.absent(),
          Value<int?> discomfortAfter = const Value.absent(),
          Value<String?> notes = const Value.absent(),
          bool? synced,
          DateTime? completedAt}) =>
      LocalSession(
        id: id ?? this.id,
        protocolId: protocolId ?? this.protocolId,
        protocolName: protocolName ?? this.protocolName,
        deviceIds: deviceIds ?? this.deviceIds,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        discomfortBefore: discomfortBefore.present
            ? discomfortBefore.value
            : this.discomfortBefore,
        discomfortAfter: discomfortAfter.present
            ? discomfortAfter.value
            : this.discomfortAfter,
        notes: notes.present ? notes.value : this.notes,
        synced: synced ?? this.synced,
        completedAt: completedAt ?? this.completedAt,
      );
  LocalSession copyWithCompanion(LocalSessionsCompanion data) {
    return LocalSession(
      id: data.id.present ? data.id.value : this.id,
      protocolId:
          data.protocolId.present ? data.protocolId.value : this.protocolId,
      protocolName: data.protocolName.present
          ? data.protocolName.value
          : this.protocolName,
      deviceIds: data.deviceIds.present ? data.deviceIds.value : this.deviceIds,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      elapsedSeconds: data.elapsedSeconds.present
          ? data.elapsedSeconds.value
          : this.elapsedSeconds,
      discomfortBefore: data.discomfortBefore.present
          ? data.discomfortBefore.value
          : this.discomfortBefore,
      discomfortAfter: data.discomfortAfter.present
          ? data.discomfortAfter.value
          : this.discomfortAfter,
      notes: data.notes.present ? data.notes.value : this.notes,
      synced: data.synced.present ? data.synced.value : this.synced,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSession(')
          ..write('id: $id, ')
          ..write('protocolId: $protocolId, ')
          ..write('protocolName: $protocolName, ')
          ..write('deviceIds: $deviceIds, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('elapsedSeconds: $elapsedSeconds, ')
          ..write('discomfortBefore: $discomfortBefore, ')
          ..write('discomfortAfter: $discomfortAfter, ')
          ..write('notes: $notes, ')
          ..write('synced: $synced, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      protocolId,
      protocolName,
      deviceIds,
      durationSeconds,
      elapsedSeconds,
      discomfortBefore,
      discomfortAfter,
      notes,
      synced,
      completedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSession &&
          other.id == this.id &&
          other.protocolId == this.protocolId &&
          other.protocolName == this.protocolName &&
          other.deviceIds == this.deviceIds &&
          other.durationSeconds == this.durationSeconds &&
          other.elapsedSeconds == this.elapsedSeconds &&
          other.discomfortBefore == this.discomfortBefore &&
          other.discomfortAfter == this.discomfortAfter &&
          other.notes == this.notes &&
          other.synced == this.synced &&
          other.completedAt == this.completedAt);
}

class LocalSessionsCompanion extends UpdateCompanion<LocalSession> {
  final Value<String> id;
  final Value<String> protocolId;
  final Value<String> protocolName;
  final Value<String> deviceIds;
  final Value<int> durationSeconds;
  final Value<int> elapsedSeconds;
  final Value<int?> discomfortBefore;
  final Value<int?> discomfortAfter;
  final Value<String?> notes;
  final Value<bool> synced;
  final Value<DateTime> completedAt;
  final Value<int> rowid;
  const LocalSessionsCompanion({
    this.id = const Value.absent(),
    this.protocolId = const Value.absent(),
    this.protocolName = const Value.absent(),
    this.deviceIds = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.elapsedSeconds = const Value.absent(),
    this.discomfortBefore = const Value.absent(),
    this.discomfortAfter = const Value.absent(),
    this.notes = const Value.absent(),
    this.synced = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSessionsCompanion.insert({
    required String id,
    required String protocolId,
    required String protocolName,
    required String deviceIds,
    required int durationSeconds,
    required int elapsedSeconds,
    this.discomfortBefore = const Value.absent(),
    this.discomfortAfter = const Value.absent(),
    this.notes = const Value.absent(),
    this.synced = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        protocolId = Value(protocolId),
        protocolName = Value(protocolName),
        deviceIds = Value(deviceIds),
        durationSeconds = Value(durationSeconds),
        elapsedSeconds = Value(elapsedSeconds);
  static Insertable<LocalSession> custom({
    Expression<String>? id,
    Expression<String>? protocolId,
    Expression<String>? protocolName,
    Expression<String>? deviceIds,
    Expression<int>? durationSeconds,
    Expression<int>? elapsedSeconds,
    Expression<int>? discomfortBefore,
    Expression<int>? discomfortAfter,
    Expression<String>? notes,
    Expression<bool>? synced,
    Expression<DateTime>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (protocolId != null) 'protocol_id': protocolId,
      if (protocolName != null) 'protocol_name': protocolName,
      if (deviceIds != null) 'device_ids': deviceIds,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (elapsedSeconds != null) 'elapsed_seconds': elapsedSeconds,
      if (discomfortBefore != null) 'discomfort_before': discomfortBefore,
      if (discomfortAfter != null) 'discomfort_after': discomfortAfter,
      if (notes != null) 'notes': notes,
      if (synced != null) 'synced': synced,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSessionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? protocolId,
      Value<String>? protocolName,
      Value<String>? deviceIds,
      Value<int>? durationSeconds,
      Value<int>? elapsedSeconds,
      Value<int?>? discomfortBefore,
      Value<int?>? discomfortAfter,
      Value<String?>? notes,
      Value<bool>? synced,
      Value<DateTime>? completedAt,
      Value<int>? rowid}) {
    return LocalSessionsCompanion(
      id: id ?? this.id,
      protocolId: protocolId ?? this.protocolId,
      protocolName: protocolName ?? this.protocolName,
      deviceIds: deviceIds ?? this.deviceIds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      discomfortBefore: discomfortBefore ?? this.discomfortBefore,
      discomfortAfter: discomfortAfter ?? this.discomfortAfter,
      notes: notes ?? this.notes,
      synced: synced ?? this.synced,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (protocolId.present) {
      map['protocol_id'] = Variable<String>(protocolId.value);
    }
    if (protocolName.present) {
      map['protocol_name'] = Variable<String>(protocolName.value);
    }
    if (deviceIds.present) {
      map['device_ids'] = Variable<String>(deviceIds.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (elapsedSeconds.present) {
      map['elapsed_seconds'] = Variable<int>(elapsedSeconds.value);
    }
    if (discomfortBefore.present) {
      map['discomfort_before'] = Variable<int>(discomfortBefore.value);
    }
    if (discomfortAfter.present) {
      map['discomfort_after'] = Variable<int>(discomfortAfter.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSessionsCompanion(')
          ..write('id: $id, ')
          ..write('protocolId: $protocolId, ')
          ..write('protocolName: $protocolName, ')
          ..write('deviceIds: $deviceIds, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('elapsedSeconds: $elapsedSeconds, ')
          ..write('discomfortBefore: $discomfortBefore, ')
          ..write('discomfortAfter: $discomfortAfter, ')
          ..write('notes: $notes, ')
          ..write('synced: $synced, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PresetsTable extends Presets with TableInfo<$PresetsTable, Preset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PresetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deviceIdsMeta =
      const VerificationMeta('deviceIds');
  @override
  late final GeneratedColumn<String> deviceIds = GeneratedColumn<String>(
      'device_ids', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _protocolIdMeta =
      const VerificationMeta('protocolId');
  @override
  late final GeneratedColumn<String> protocolId = GeneratedColumn<String>(
      'protocol_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _advancedSettingsJsonMeta =
      const VerificationMeta('advancedSettingsJson');
  @override
  late final GeneratedColumn<String> advancedSettingsJson =
      GeneratedColumn<String>('advanced_settings_json', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('{}'));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        deviceIds,
        protocolId,
        advancedSettingsJson,
        sortOrder,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'presets';
  @override
  VerificationContext validateIntegrity(Insertable<Preset> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('device_ids')) {
      context.handle(_deviceIdsMeta,
          deviceIds.isAcceptableOrUnknown(data['device_ids']!, _deviceIdsMeta));
    } else if (isInserting) {
      context.missing(_deviceIdsMeta);
    }
    if (data.containsKey('protocol_id')) {
      context.handle(
          _protocolIdMeta,
          protocolId.isAcceptableOrUnknown(
              data['protocol_id']!, _protocolIdMeta));
    } else if (isInserting) {
      context.missing(_protocolIdMeta);
    }
    if (data.containsKey('advanced_settings_json')) {
      context.handle(
          _advancedSettingsJsonMeta,
          advancedSettingsJson.isAcceptableOrUnknown(
              data['advanced_settings_json']!, _advancedSettingsJsonMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Preset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Preset(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      deviceIds: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_ids'])!,
      protocolId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}protocol_id'])!,
      advancedSettingsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}advanced_settings_json'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $PresetsTable createAlias(String alias) {
    return $PresetsTable(attachedDatabase, alias);
  }
}

class Preset extends DataClass implements Insertable<Preset> {
  final String id;
  final String name;
  final String deviceIds;
  final String protocolId;
  final String advancedSettingsJson;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Preset(
      {required this.id,
      required this.name,
      required this.deviceIds,
      required this.protocolId,
      required this.advancedSettingsJson,
      required this.sortOrder,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['device_ids'] = Variable<String>(deviceIds);
    map['protocol_id'] = Variable<String>(protocolId);
    map['advanced_settings_json'] = Variable<String>(advancedSettingsJson);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PresetsCompanion toCompanion(bool nullToAbsent) {
    return PresetsCompanion(
      id: Value(id),
      name: Value(name),
      deviceIds: Value(deviceIds),
      protocolId: Value(protocolId),
      advancedSettingsJson: Value(advancedSettingsJson),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Preset.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Preset(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      deviceIds: serializer.fromJson<String>(json['deviceIds']),
      protocolId: serializer.fromJson<String>(json['protocolId']),
      advancedSettingsJson:
          serializer.fromJson<String>(json['advancedSettingsJson']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'deviceIds': serializer.toJson<String>(deviceIds),
      'protocolId': serializer.toJson<String>(protocolId),
      'advancedSettingsJson': serializer.toJson<String>(advancedSettingsJson),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Preset copyWith(
          {String? id,
          String? name,
          String? deviceIds,
          String? protocolId,
          String? advancedSettingsJson,
          int? sortOrder,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Preset(
        id: id ?? this.id,
        name: name ?? this.name,
        deviceIds: deviceIds ?? this.deviceIds,
        protocolId: protocolId ?? this.protocolId,
        advancedSettingsJson: advancedSettingsJson ?? this.advancedSettingsJson,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Preset copyWithCompanion(PresetsCompanion data) {
    return Preset(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      deviceIds: data.deviceIds.present ? data.deviceIds.value : this.deviceIds,
      protocolId:
          data.protocolId.present ? data.protocolId.value : this.protocolId,
      advancedSettingsJson: data.advancedSettingsJson.present
          ? data.advancedSettingsJson.value
          : this.advancedSettingsJson,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Preset(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('deviceIds: $deviceIds, ')
          ..write('protocolId: $protocolId, ')
          ..write('advancedSettingsJson: $advancedSettingsJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, deviceIds, protocolId,
      advancedSettingsJson, sortOrder, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Preset &&
          other.id == this.id &&
          other.name == this.name &&
          other.deviceIds == this.deviceIds &&
          other.protocolId == this.protocolId &&
          other.advancedSettingsJson == this.advancedSettingsJson &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PresetsCompanion extends UpdateCompanion<Preset> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> deviceIds;
  final Value<String> protocolId;
  final Value<String> advancedSettingsJson;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PresetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.deviceIds = const Value.absent(),
    this.protocolId = const Value.absent(),
    this.advancedSettingsJson = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PresetsCompanion.insert({
    required String id,
    required String name,
    required String deviceIds,
    required String protocolId,
    this.advancedSettingsJson = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        deviceIds = Value(deviceIds),
        protocolId = Value(protocolId);
  static Insertable<Preset> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? deviceIds,
    Expression<String>? protocolId,
    Expression<String>? advancedSettingsJson,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (deviceIds != null) 'device_ids': deviceIds,
      if (protocolId != null) 'protocol_id': protocolId,
      if (advancedSettingsJson != null)
        'advanced_settings_json': advancedSettingsJson,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PresetsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? deviceIds,
      Value<String>? protocolId,
      Value<String>? advancedSettingsJson,
      Value<int>? sortOrder,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return PresetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceIds: deviceIds ?? this.deviceIds,
      protocolId: protocolId ?? this.protocolId,
      advancedSettingsJson: advancedSettingsJson ?? this.advancedSettingsJson,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (deviceIds.present) {
      map['device_ids'] = Variable<String>(deviceIds.value);
    }
    if (protocolId.present) {
      map['protocol_id'] = Variable<String>(protocolId.value);
    }
    if (advancedSettingsJson.present) {
      map['advanced_settings_json'] =
          Variable<String>(advancedSettingsJson.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PresetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('deviceIds: $deviceIds, ')
          ..write('protocolId: $protocolId, ')
          ..write('advancedSettingsJson: $advancedSettingsJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CommandQueueTable extends CommandQueue
    with TableInfo<$CommandQueueTable, CommandQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CommandQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _macAddressMeta =
      const VerificationMeta('macAddress');
  @override
  late final GeneratedColumn<String> macAddress = GeneratedColumn<String>(
      'mac_address', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _commandJsonMeta =
      const VerificationMeta('commandJson');
  @override
  late final GeneratedColumn<String> commandJson = GeneratedColumn<String>(
      'command_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
      'synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("synced" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, macAddress, commandJson, synced, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'command_queue';
  @override
  VerificationContext validateIntegrity(Insertable<CommandQueueData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('mac_address')) {
      context.handle(
          _macAddressMeta,
          macAddress.isAcceptableOrUnknown(
              data['mac_address']!, _macAddressMeta));
    } else if (isInserting) {
      context.missing(_macAddressMeta);
    }
    if (data.containsKey('command_json')) {
      context.handle(
          _commandJsonMeta,
          commandJson.isAcceptableOrUnknown(
              data['command_json']!, _commandJsonMeta));
    } else if (isInserting) {
      context.missing(_commandJsonMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(_syncedMeta,
          synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CommandQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CommandQueueData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      macAddress: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mac_address'])!,
      commandJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}command_json'])!,
      synced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}synced'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $CommandQueueTable createAlias(String alias) {
    return $CommandQueueTable(attachedDatabase, alias);
  }
}

class CommandQueueData extends DataClass
    implements Insertable<CommandQueueData> {
  final int id;
  final String macAddress;
  final String commandJson;
  final bool synced;
  final DateTime createdAt;
  const CommandQueueData(
      {required this.id,
      required this.macAddress,
      required this.commandJson,
      required this.synced,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['mac_address'] = Variable<String>(macAddress);
    map['command_json'] = Variable<String>(commandJson);
    map['synced'] = Variable<bool>(synced);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CommandQueueCompanion toCompanion(bool nullToAbsent) {
    return CommandQueueCompanion(
      id: Value(id),
      macAddress: Value(macAddress),
      commandJson: Value(commandJson),
      synced: Value(synced),
      createdAt: Value(createdAt),
    );
  }

  factory CommandQueueData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CommandQueueData(
      id: serializer.fromJson<int>(json['id']),
      macAddress: serializer.fromJson<String>(json['macAddress']),
      commandJson: serializer.fromJson<String>(json['commandJson']),
      synced: serializer.fromJson<bool>(json['synced']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'macAddress': serializer.toJson<String>(macAddress),
      'commandJson': serializer.toJson<String>(commandJson),
      'synced': serializer.toJson<bool>(synced),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CommandQueueData copyWith(
          {int? id,
          String? macAddress,
          String? commandJson,
          bool? synced,
          DateTime? createdAt}) =>
      CommandQueueData(
        id: id ?? this.id,
        macAddress: macAddress ?? this.macAddress,
        commandJson: commandJson ?? this.commandJson,
        synced: synced ?? this.synced,
        createdAt: createdAt ?? this.createdAt,
      );
  CommandQueueData copyWithCompanion(CommandQueueCompanion data) {
    return CommandQueueData(
      id: data.id.present ? data.id.value : this.id,
      macAddress:
          data.macAddress.present ? data.macAddress.value : this.macAddress,
      commandJson:
          data.commandJson.present ? data.commandJson.value : this.commandJson,
      synced: data.synced.present ? data.synced.value : this.synced,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CommandQueueData(')
          ..write('id: $id, ')
          ..write('macAddress: $macAddress, ')
          ..write('commandJson: $commandJson, ')
          ..write('synced: $synced, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, macAddress, commandJson, synced, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CommandQueueData &&
          other.id == this.id &&
          other.macAddress == this.macAddress &&
          other.commandJson == this.commandJson &&
          other.synced == this.synced &&
          other.createdAt == this.createdAt);
}

class CommandQueueCompanion extends UpdateCompanion<CommandQueueData> {
  final Value<int> id;
  final Value<String> macAddress;
  final Value<String> commandJson;
  final Value<bool> synced;
  final Value<DateTime> createdAt;
  const CommandQueueCompanion({
    this.id = const Value.absent(),
    this.macAddress = const Value.absent(),
    this.commandJson = const Value.absent(),
    this.synced = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CommandQueueCompanion.insert({
    this.id = const Value.absent(),
    required String macAddress,
    required String commandJson,
    this.synced = const Value.absent(),
    this.createdAt = const Value.absent(),
  })  : macAddress = Value(macAddress),
        commandJson = Value(commandJson);
  static Insertable<CommandQueueData> custom({
    Expression<int>? id,
    Expression<String>? macAddress,
    Expression<String>? commandJson,
    Expression<bool>? synced,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (macAddress != null) 'mac_address': macAddress,
      if (commandJson != null) 'command_json': commandJson,
      if (synced != null) 'synced': synced,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CommandQueueCompanion copyWith(
      {Value<int>? id,
      Value<String>? macAddress,
      Value<String>? commandJson,
      Value<bool>? synced,
      Value<DateTime>? createdAt}) {
    return CommandQueueCompanion(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      commandJson: commandJson ?? this.commandJson,
      synced: synced ?? this.synced,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (macAddress.present) {
      map['mac_address'] = Variable<String>(macAddress.value);
    }
    if (commandJson.present) {
      map['command_json'] = Variable<String>(commandJson.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CommandQueueCompanion(')
          ..write('id: $id, ')
          ..write('macAddress: $macAddress, ')
          ..write('commandJson: $commandJson, ')
          ..write('synced: $synced, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PairedDevicesTable pairedDevices = $PairedDevicesTable(this);
  late final $CachedProtocolsTable cachedProtocols =
      $CachedProtocolsTable(this);
  late final $LocalSessionsTable localSessions = $LocalSessionsTable(this);
  late final $PresetsTable presets = $PresetsTable(this);
  late final $CommandQueueTable commandQueue = $CommandQueueTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [pairedDevices, cachedProtocols, localSessions, presets, commandQueue];
}

typedef $$PairedDevicesTableCreateCompanionBuilder = PairedDevicesCompanion
    Function({
  required String id,
  required String macAddress,
  required String name,
  Value<bool> autoReconnect,
  Value<DateTime?> lastConnected,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$PairedDevicesTableUpdateCompanionBuilder = PairedDevicesCompanion
    Function({
  Value<String> id,
  Value<String> macAddress,
  Value<String> name,
  Value<bool> autoReconnect,
  Value<DateTime?> lastConnected,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$PairedDevicesTableFilterComposer
    extends Composer<_$AppDatabase, $PairedDevicesTable> {
  $$PairedDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get macAddress => $composableBuilder(
      column: $table.macAddress, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get autoReconnect => $composableBuilder(
      column: $table.autoReconnect, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastConnected => $composableBuilder(
      column: $table.lastConnected, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$PairedDevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $PairedDevicesTable> {
  $$PairedDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get macAddress => $composableBuilder(
      column: $table.macAddress, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get autoReconnect => $composableBuilder(
      column: $table.autoReconnect,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastConnected => $composableBuilder(
      column: $table.lastConnected,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$PairedDevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PairedDevicesTable> {
  $$PairedDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get macAddress => $composableBuilder(
      column: $table.macAddress, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get autoReconnect => $composableBuilder(
      column: $table.autoReconnect, builder: (column) => column);

  GeneratedColumn<DateTime> get lastConnected => $composableBuilder(
      column: $table.lastConnected, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PairedDevicesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PairedDevicesTable,
    PairedDevice,
    $$PairedDevicesTableFilterComposer,
    $$PairedDevicesTableOrderingComposer,
    $$PairedDevicesTableAnnotationComposer,
    $$PairedDevicesTableCreateCompanionBuilder,
    $$PairedDevicesTableUpdateCompanionBuilder,
    (
      PairedDevice,
      BaseReferences<_$AppDatabase, $PairedDevicesTable, PairedDevice>
    ),
    PairedDevice,
    PrefetchHooks Function()> {
  $$PairedDevicesTableTableManager(_$AppDatabase db, $PairedDevicesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PairedDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PairedDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PairedDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> macAddress = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<bool> autoReconnect = const Value.absent(),
            Value<DateTime?> lastConnected = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PairedDevicesCompanion(
            id: id,
            macAddress: macAddress,
            name: name,
            autoReconnect: autoReconnect,
            lastConnected: lastConnected,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String macAddress,
            required String name,
            Value<bool> autoReconnect = const Value.absent(),
            Value<DateTime?> lastConnected = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PairedDevicesCompanion.insert(
            id: id,
            macAddress: macAddress,
            name: name,
            autoReconnect: autoReconnect,
            lastConnected: lastConnected,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PairedDevicesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PairedDevicesTable,
    PairedDevice,
    $$PairedDevicesTableFilterComposer,
    $$PairedDevicesTableOrderingComposer,
    $$PairedDevicesTableAnnotationComposer,
    $$PairedDevicesTableCreateCompanionBuilder,
    $$PairedDevicesTableUpdateCompanionBuilder,
    (
      PairedDevice,
      BaseReferences<_$AppDatabase, $PairedDevicesTable, PairedDevice>
    ),
    PairedDevice,
    PrefetchHooks Function()>;
typedef $$CachedProtocolsTableCreateCompanionBuilder = CachedProtocolsCompanion
    Function({
  required String id,
  required String templateName,
  Value<int> sessions,
  required String cyclesJson,
  Value<double> hotdrop,
  Value<double> colddrop,
  Value<double> vibmin,
  Value<double> vibmax,
  Value<bool> cycle1,
  Value<bool> cycle5,
  Value<double> edgecycleduration,
  Value<double> sessionPause,
  Value<String> description,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});
typedef $$CachedProtocolsTableUpdateCompanionBuilder = CachedProtocolsCompanion
    Function({
  Value<String> id,
  Value<String> templateName,
  Value<int> sessions,
  Value<String> cyclesJson,
  Value<double> hotdrop,
  Value<double> colddrop,
  Value<double> vibmin,
  Value<double> vibmax,
  Value<bool> cycle1,
  Value<bool> cycle5,
  Value<double> edgecycleduration,
  Value<double> sessionPause,
  Value<String> description,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$CachedProtocolsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedProtocolsTable> {
  $$CachedProtocolsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get templateName => $composableBuilder(
      column: $table.templateName, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sessions => $composableBuilder(
      column: $table.sessions, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cyclesJson => $composableBuilder(
      column: $table.cyclesJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get hotdrop => $composableBuilder(
      column: $table.hotdrop, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get colddrop => $composableBuilder(
      column: $table.colddrop, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get vibmin => $composableBuilder(
      column: $table.vibmin, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get vibmax => $composableBuilder(
      column: $table.vibmax, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get cycle1 => $composableBuilder(
      column: $table.cycle1, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get cycle5 => $composableBuilder(
      column: $table.cycle5, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get edgecycleduration => $composableBuilder(
      column: $table.edgecycleduration,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get sessionPause => $composableBuilder(
      column: $table.sessionPause, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedProtocolsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedProtocolsTable> {
  $$CachedProtocolsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get templateName => $composableBuilder(
      column: $table.templateName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sessions => $composableBuilder(
      column: $table.sessions, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cyclesJson => $composableBuilder(
      column: $table.cyclesJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get hotdrop => $composableBuilder(
      column: $table.hotdrop, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get colddrop => $composableBuilder(
      column: $table.colddrop, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get vibmin => $composableBuilder(
      column: $table.vibmin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get vibmax => $composableBuilder(
      column: $table.vibmax, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get cycle1 => $composableBuilder(
      column: $table.cycle1, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get cycle5 => $composableBuilder(
      column: $table.cycle5, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get edgecycleduration => $composableBuilder(
      column: $table.edgecycleduration,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get sessionPause => $composableBuilder(
      column: $table.sessionPause,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedProtocolsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedProtocolsTable> {
  $$CachedProtocolsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get templateName => $composableBuilder(
      column: $table.templateName, builder: (column) => column);

  GeneratedColumn<int> get sessions =>
      $composableBuilder(column: $table.sessions, builder: (column) => column);

  GeneratedColumn<String> get cyclesJson => $composableBuilder(
      column: $table.cyclesJson, builder: (column) => column);

  GeneratedColumn<double> get hotdrop =>
      $composableBuilder(column: $table.hotdrop, builder: (column) => column);

  GeneratedColumn<double> get colddrop =>
      $composableBuilder(column: $table.colddrop, builder: (column) => column);

  GeneratedColumn<double> get vibmin =>
      $composableBuilder(column: $table.vibmin, builder: (column) => column);

  GeneratedColumn<double> get vibmax =>
      $composableBuilder(column: $table.vibmax, builder: (column) => column);

  GeneratedColumn<bool> get cycle1 =>
      $composableBuilder(column: $table.cycle1, builder: (column) => column);

  GeneratedColumn<bool> get cycle5 =>
      $composableBuilder(column: $table.cycle5, builder: (column) => column);

  GeneratedColumn<double> get edgecycleduration => $composableBuilder(
      column: $table.edgecycleduration, builder: (column) => column);

  GeneratedColumn<double> get sessionPause => $composableBuilder(
      column: $table.sessionPause, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedProtocolsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedProtocolsTable,
    CachedProtocol,
    $$CachedProtocolsTableFilterComposer,
    $$CachedProtocolsTableOrderingComposer,
    $$CachedProtocolsTableAnnotationComposer,
    $$CachedProtocolsTableCreateCompanionBuilder,
    $$CachedProtocolsTableUpdateCompanionBuilder,
    (
      CachedProtocol,
      BaseReferences<_$AppDatabase, $CachedProtocolsTable, CachedProtocol>
    ),
    CachedProtocol,
    PrefetchHooks Function()> {
  $$CachedProtocolsTableTableManager(
      _$AppDatabase db, $CachedProtocolsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedProtocolsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedProtocolsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedProtocolsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> templateName = const Value.absent(),
            Value<int> sessions = const Value.absent(),
            Value<String> cyclesJson = const Value.absent(),
            Value<double> hotdrop = const Value.absent(),
            Value<double> colddrop = const Value.absent(),
            Value<double> vibmin = const Value.absent(),
            Value<double> vibmax = const Value.absent(),
            Value<bool> cycle1 = const Value.absent(),
            Value<bool> cycle5 = const Value.absent(),
            Value<double> edgecycleduration = const Value.absent(),
            Value<double> sessionPause = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedProtocolsCompanion(
            id: id,
            templateName: templateName,
            sessions: sessions,
            cyclesJson: cyclesJson,
            hotdrop: hotdrop,
            colddrop: colddrop,
            vibmin: vibmin,
            vibmax: vibmax,
            cycle1: cycle1,
            cycle5: cycle5,
            edgecycleduration: edgecycleduration,
            sessionPause: sessionPause,
            description: description,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String templateName,
            Value<int> sessions = const Value.absent(),
            required String cyclesJson,
            Value<double> hotdrop = const Value.absent(),
            Value<double> colddrop = const Value.absent(),
            Value<double> vibmin = const Value.absent(),
            Value<double> vibmax = const Value.absent(),
            Value<bool> cycle1 = const Value.absent(),
            Value<bool> cycle5 = const Value.absent(),
            Value<double> edgecycleduration = const Value.absent(),
            Value<double> sessionPause = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedProtocolsCompanion.insert(
            id: id,
            templateName: templateName,
            sessions: sessions,
            cyclesJson: cyclesJson,
            hotdrop: hotdrop,
            colddrop: colddrop,
            vibmin: vibmin,
            vibmax: vibmax,
            cycle1: cycle1,
            cycle5: cycle5,
            edgecycleduration: edgecycleduration,
            sessionPause: sessionPause,
            description: description,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedProtocolsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedProtocolsTable,
    CachedProtocol,
    $$CachedProtocolsTableFilterComposer,
    $$CachedProtocolsTableOrderingComposer,
    $$CachedProtocolsTableAnnotationComposer,
    $$CachedProtocolsTableCreateCompanionBuilder,
    $$CachedProtocolsTableUpdateCompanionBuilder,
    (
      CachedProtocol,
      BaseReferences<_$AppDatabase, $CachedProtocolsTable, CachedProtocol>
    ),
    CachedProtocol,
    PrefetchHooks Function()>;
typedef $$LocalSessionsTableCreateCompanionBuilder = LocalSessionsCompanion
    Function({
  required String id,
  required String protocolId,
  required String protocolName,
  required String deviceIds,
  required int durationSeconds,
  required int elapsedSeconds,
  Value<int?> discomfortBefore,
  Value<int?> discomfortAfter,
  Value<String?> notes,
  Value<bool> synced,
  Value<DateTime> completedAt,
  Value<int> rowid,
});
typedef $$LocalSessionsTableUpdateCompanionBuilder = LocalSessionsCompanion
    Function({
  Value<String> id,
  Value<String> protocolId,
  Value<String> protocolName,
  Value<String> deviceIds,
  Value<int> durationSeconds,
  Value<int> elapsedSeconds,
  Value<int?> discomfortBefore,
  Value<int?> discomfortAfter,
  Value<String?> notes,
  Value<bool> synced,
  Value<DateTime> completedAt,
  Value<int> rowid,
});

class $$LocalSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalSessionsTable> {
  $$LocalSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get protocolId => $composableBuilder(
      column: $table.protocolId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get protocolName => $composableBuilder(
      column: $table.protocolName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceIds => $composableBuilder(
      column: $table.deviceIds, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get elapsedSeconds => $composableBuilder(
      column: $table.elapsedSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get discomfortBefore => $composableBuilder(
      column: $table.discomfortBefore,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get discomfortAfter => $composableBuilder(
      column: $table.discomfortAfter,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalSessionsTable> {
  $$LocalSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get protocolId => $composableBuilder(
      column: $table.protocolId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get protocolName => $composableBuilder(
      column: $table.protocolName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceIds => $composableBuilder(
      column: $table.deviceIds, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get elapsedSeconds => $composableBuilder(
      column: $table.elapsedSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get discomfortBefore => $composableBuilder(
      column: $table.discomfortBefore,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get discomfortAfter => $composableBuilder(
      column: $table.discomfortAfter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalSessionsTable> {
  $$LocalSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get protocolId => $composableBuilder(
      column: $table.protocolId, builder: (column) => column);

  GeneratedColumn<String> get protocolName => $composableBuilder(
      column: $table.protocolName, builder: (column) => column);

  GeneratedColumn<String> get deviceIds =>
      $composableBuilder(column: $table.deviceIds, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds, builder: (column) => column);

  GeneratedColumn<int> get elapsedSeconds => $composableBuilder(
      column: $table.elapsedSeconds, builder: (column) => column);

  GeneratedColumn<int> get discomfortBefore => $composableBuilder(
      column: $table.discomfortBefore, builder: (column) => column);

  GeneratedColumn<int> get discomfortAfter => $composableBuilder(
      column: $table.discomfortAfter, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);
}

class $$LocalSessionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalSessionsTable,
    LocalSession,
    $$LocalSessionsTableFilterComposer,
    $$LocalSessionsTableOrderingComposer,
    $$LocalSessionsTableAnnotationComposer,
    $$LocalSessionsTableCreateCompanionBuilder,
    $$LocalSessionsTableUpdateCompanionBuilder,
    (
      LocalSession,
      BaseReferences<_$AppDatabase, $LocalSessionsTable, LocalSession>
    ),
    LocalSession,
    PrefetchHooks Function()> {
  $$LocalSessionsTableTableManager(_$AppDatabase db, $LocalSessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> protocolId = const Value.absent(),
            Value<String> protocolName = const Value.absent(),
            Value<String> deviceIds = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            Value<int> elapsedSeconds = const Value.absent(),
            Value<int?> discomfortBefore = const Value.absent(),
            Value<int?> discomfortAfter = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<bool> synced = const Value.absent(),
            Value<DateTime> completedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSessionsCompanion(
            id: id,
            protocolId: protocolId,
            protocolName: protocolName,
            deviceIds: deviceIds,
            durationSeconds: durationSeconds,
            elapsedSeconds: elapsedSeconds,
            discomfortBefore: discomfortBefore,
            discomfortAfter: discomfortAfter,
            notes: notes,
            synced: synced,
            completedAt: completedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String protocolId,
            required String protocolName,
            required String deviceIds,
            required int durationSeconds,
            required int elapsedSeconds,
            Value<int?> discomfortBefore = const Value.absent(),
            Value<int?> discomfortAfter = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<bool> synced = const Value.absent(),
            Value<DateTime> completedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSessionsCompanion.insert(
            id: id,
            protocolId: protocolId,
            protocolName: protocolName,
            deviceIds: deviceIds,
            durationSeconds: durationSeconds,
            elapsedSeconds: elapsedSeconds,
            discomfortBefore: discomfortBefore,
            discomfortAfter: discomfortAfter,
            notes: notes,
            synced: synced,
            completedAt: completedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalSessionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalSessionsTable,
    LocalSession,
    $$LocalSessionsTableFilterComposer,
    $$LocalSessionsTableOrderingComposer,
    $$LocalSessionsTableAnnotationComposer,
    $$LocalSessionsTableCreateCompanionBuilder,
    $$LocalSessionsTableUpdateCompanionBuilder,
    (
      LocalSession,
      BaseReferences<_$AppDatabase, $LocalSessionsTable, LocalSession>
    ),
    LocalSession,
    PrefetchHooks Function()>;
typedef $$PresetsTableCreateCompanionBuilder = PresetsCompanion Function({
  required String id,
  required String name,
  required String deviceIds,
  required String protocolId,
  Value<String> advancedSettingsJson,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$PresetsTableUpdateCompanionBuilder = PresetsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> deviceIds,
  Value<String> protocolId,
  Value<String> advancedSettingsJson,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$PresetsTableFilterComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceIds => $composableBuilder(
      column: $table.deviceIds, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get protocolId => $composableBuilder(
      column: $table.protocolId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get advancedSettingsJson => $composableBuilder(
      column: $table.advancedSettingsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$PresetsTableOrderingComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceIds => $composableBuilder(
      column: $table.deviceIds, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get protocolId => $composableBuilder(
      column: $table.protocolId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get advancedSettingsJson => $composableBuilder(
      column: $table.advancedSettingsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$PresetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get deviceIds =>
      $composableBuilder(column: $table.deviceIds, builder: (column) => column);

  GeneratedColumn<String> get protocolId => $composableBuilder(
      column: $table.protocolId, builder: (column) => column);

  GeneratedColumn<String> get advancedSettingsJson => $composableBuilder(
      column: $table.advancedSettingsJson, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PresetsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PresetsTable,
    Preset,
    $$PresetsTableFilterComposer,
    $$PresetsTableOrderingComposer,
    $$PresetsTableAnnotationComposer,
    $$PresetsTableCreateCompanionBuilder,
    $$PresetsTableUpdateCompanionBuilder,
    (Preset, BaseReferences<_$AppDatabase, $PresetsTable, Preset>),
    Preset,
    PrefetchHooks Function()> {
  $$PresetsTableTableManager(_$AppDatabase db, $PresetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PresetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PresetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PresetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> deviceIds = const Value.absent(),
            Value<String> protocolId = const Value.absent(),
            Value<String> advancedSettingsJson = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PresetsCompanion(
            id: id,
            name: name,
            deviceIds: deviceIds,
            protocolId: protocolId,
            advancedSettingsJson: advancedSettingsJson,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String deviceIds,
            required String protocolId,
            Value<String> advancedSettingsJson = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PresetsCompanion.insert(
            id: id,
            name: name,
            deviceIds: deviceIds,
            protocolId: protocolId,
            advancedSettingsJson: advancedSettingsJson,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PresetsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PresetsTable,
    Preset,
    $$PresetsTableFilterComposer,
    $$PresetsTableOrderingComposer,
    $$PresetsTableAnnotationComposer,
    $$PresetsTableCreateCompanionBuilder,
    $$PresetsTableUpdateCompanionBuilder,
    (Preset, BaseReferences<_$AppDatabase, $PresetsTable, Preset>),
    Preset,
    PrefetchHooks Function()>;
typedef $$CommandQueueTableCreateCompanionBuilder = CommandQueueCompanion
    Function({
  Value<int> id,
  required String macAddress,
  required String commandJson,
  Value<bool> synced,
  Value<DateTime> createdAt,
});
typedef $$CommandQueueTableUpdateCompanionBuilder = CommandQueueCompanion
    Function({
  Value<int> id,
  Value<String> macAddress,
  Value<String> commandJson,
  Value<bool> synced,
  Value<DateTime> createdAt,
});

class $$CommandQueueTableFilterComposer
    extends Composer<_$AppDatabase, $CommandQueueTable> {
  $$CommandQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get macAddress => $composableBuilder(
      column: $table.macAddress, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get commandJson => $composableBuilder(
      column: $table.commandJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$CommandQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $CommandQueueTable> {
  $$CommandQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get macAddress => $composableBuilder(
      column: $table.macAddress, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get commandJson => $composableBuilder(
      column: $table.commandJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$CommandQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $CommandQueueTable> {
  $$CommandQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get macAddress => $composableBuilder(
      column: $table.macAddress, builder: (column) => column);

  GeneratedColumn<String> get commandJson => $composableBuilder(
      column: $table.commandJson, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CommandQueueTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CommandQueueTable,
    CommandQueueData,
    $$CommandQueueTableFilterComposer,
    $$CommandQueueTableOrderingComposer,
    $$CommandQueueTableAnnotationComposer,
    $$CommandQueueTableCreateCompanionBuilder,
    $$CommandQueueTableUpdateCompanionBuilder,
    (
      CommandQueueData,
      BaseReferences<_$AppDatabase, $CommandQueueTable, CommandQueueData>
    ),
    CommandQueueData,
    PrefetchHooks Function()> {
  $$CommandQueueTableTableManager(_$AppDatabase db, $CommandQueueTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CommandQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CommandQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CommandQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> macAddress = const Value.absent(),
            Value<String> commandJson = const Value.absent(),
            Value<bool> synced = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              CommandQueueCompanion(
            id: id,
            macAddress: macAddress,
            commandJson: commandJson,
            synced: synced,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String macAddress,
            required String commandJson,
            Value<bool> synced = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              CommandQueueCompanion.insert(
            id: id,
            macAddress: macAddress,
            commandJson: commandJson,
            synced: synced,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CommandQueueTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CommandQueueTable,
    CommandQueueData,
    $$CommandQueueTableFilterComposer,
    $$CommandQueueTableOrderingComposer,
    $$CommandQueueTableAnnotationComposer,
    $$CommandQueueTableCreateCompanionBuilder,
    $$CommandQueueTableUpdateCompanionBuilder,
    (
      CommandQueueData,
      BaseReferences<_$AppDatabase, $CommandQueueTable, CommandQueueData>
    ),
    CommandQueueData,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PairedDevicesTableTableManager get pairedDevices =>
      $$PairedDevicesTableTableManager(_db, _db.pairedDevices);
  $$CachedProtocolsTableTableManager get cachedProtocols =>
      $$CachedProtocolsTableTableManager(_db, _db.cachedProtocols);
  $$LocalSessionsTableTableManager get localSessions =>
      $$LocalSessionsTableTableManager(_db, _db.localSessions);
  $$PresetsTableTableManager get presets =>
      $$PresetsTableTableManager(_db, _db.presets);
  $$CommandQueueTableTableManager get commandQueue =>
      $$CommandQueueTableTableManager(_db, _db.commandQueue);
}
