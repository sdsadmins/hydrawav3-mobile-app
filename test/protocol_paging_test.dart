import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/storage/local_db.dart';
import 'package:hydrawav3/features/protocols/data/protocol_remote_source.dart';
import 'package:hydrawav3/features/protocols/data/protocol_repository.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';

Protocol _p(String id) =>
    Protocol.fromJson({'_id': id, 'template_name': 'P $id', 'cycles': []});

/// Serves [pages] in order; like the live server, every page also repeats
/// the same Protocol Plus stacks ([plus]).
class _FakeRemote extends ProtocolRemoteSource {
  final List<List<String>> pages;
  final List<String> plus;
  final calls = <int>[];
  _FakeRemote(this.pages, {this.plus = const []}) : super(Dio());

  @override
  Future<({List<Protocol> items, bool hasNextPage})> getProtocolsPage({
    int page = 1,
    int perPage = 100,
    String? orgId,
  }) async {
    calls.add(page);
    final regular = page <= pages.length ? pages[page - 1] : const <String>[];
    return (
      items: [...regular, ...plus].map(_p).toList(),
      hasNextPage: page < pages.length,
    );
  }
}

/// No local cache: every call fails and the repository carries on.
class _NoDb implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('no db in tests');
}

ProtocolRepository _repo(_FakeRemote remote) => ProtocolRepository(
      remoteSource: remote,
      db: _NoDb(),
      isOnline: true,
      orgId: '493',
    );

void main() {
  test('walks every page, not just the first', () async {
    final remote = _FakeRemote([
      [for (var i = 0; i < 100; i++) 'a$i'],
      [for (var i = 0; i < 100; i++) 'b$i'],
      ['c0', 'c1'],
    ]);
    final all = await _repo(remote).getProtocols();
    expect(remote.calls, [1, 2, 3]);
    expect(all.length, 202);
  });

  test('Protocol Plus stacks repeated on every page appear once', () async {
    final remote = _FakeRemote([
      ['r1', 'r2'],
      ['r3'],
    ], plus: ['plus1', 'plus2']);
    final ids = (await _repo(remote).getProtocols()).map((p) => p.id).toList();
    expect(ids, ['r1', 'r2', 'plus1', 'plus2', 'r3']);
  });

  test('a single page makes a single call', () async {
    final remote = _FakeRemote([
      ['r1'],
    ], plus: ['plus1']);
    expect((await _repo(remote).getProtocols()).length, 2);
    expect(remote.calls, [1]);
  });
}
