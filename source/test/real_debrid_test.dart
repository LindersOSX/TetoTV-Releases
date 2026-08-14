import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_models.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_stream_resolver.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Real-Debrid torrent selection', () {
    test('selects the video matching the requested episode in a batch', () {
      final selected = selectEpisodeFile(const [
        RealDebridTorrentFile(
          id: 1,
          path: '/Show - 01.mkv',
          bytes: 900,
          selected: false,
        ),
        RealDebridTorrentFile(
          id: 2,
          path: '/Show - 02.mkv',
          bytes: 950,
          selected: false,
        ),
        RealDebridTorrentFile(
          id: 3,
          path: '/cover.jpg',
          bytes: 20,
          selected: false,
        ),
      ], 2);

      expect(selected.id, 2);
    });

    test('falls back to the largest playable file', () {
      final selected = selectEpisodeFile(const [
        RealDebridTorrentFile(
          id: 10,
          path: '/feature-a.mkv',
          bytes: 400,
          selected: false,
        ),
        RealDebridTorrentFile(
          id: 11,
          path: '/feature-b.mp4',
          bytes: 800,
          selected: false,
        ),
      ], 12);

      expect(selected.id, 11);
    });

    test('honors a Stremio file index', () {
      final selected = selectEpisodeFile(
        const [
          RealDebridTorrentFile(
            id: 1,
            path: '/Episode 01.mkv',
            bytes: 900,
            selected: false,
          ),
          RealDebridTorrentFile(
            id: 2,
            path: '/Episode 02.mkv',
            bytes: 1000,
            selected: false,
          ),
        ],
        1,
        preferredFileIndex: 1,
      );

      expect(selected.id, 2);
    });

    test('maps a downloaded batch episode to its corresponding link', () {
      final link = selectEpisodeDownloadLink(
        const RealDebridTorrentInfo(
          id: 'batch',
          filename: 'Show batch',
          status: 'downloaded',
          progress: 100,
          files: [
            RealDebridTorrentFile(
              id: 10,
              path: '/Show - 01.mkv',
              bytes: 900,
              selected: true,
            ),
            RealDebridTorrentFile(
              id: 11,
              path: '/cover.jpg',
              bytes: 20,
              selected: false,
            ),
            RealDebridTorrentFile(
              id: 12,
              path: '/Show - 02.mkv',
              bytes: 950,
              selected: true,
            ),
          ],
          links: [
            'https://rd.example/episode-1',
            'https://rd.example/episode-2',
          ],
        ),
        2,
      );

      expect(link, 'https://rd.example/episode-2');
    });
  });

  group('Real-Debrid API failures', () {
    test('classifies code 35 as a safe release-specific failure', () {
      final error = RealDebridException.fromApi(code: 35, httpStatus: 403);

      expect(error.kind, RealDebridFailureKind.releaseUnavailable);
      expect(error.isCandidateSpecific, isTrue);
      expect(error.isTerminalAccountFailure, isFalse);
      expect(error.toString(), isNot(contains('infringing_file')));
      expect(error.toString(), contains('different release'));
    });

    test('classifies invalid authorization as terminal', () {
      final error = RealDebridException.fromApi(code: 8, httpStatus: 401);

      expect(error.kind, RealDebridFailureKind.authorization);
      expect(error.isTerminalAccountFailure, isTrue);
      expect(error.toString(), contains('Reconnect'));
    });

    test('does not fan out account-capacity or rate-limit failures', () {
      final activeDownloads = RealDebridException.fromApi(code: 21);
      final tooManyRequests = RealDebridException.fromApi(code: 34);

      expect(activeDownloads.kind, RealDebridFailureKind.account);
      expect(activeDownloads.isTerminalAccountFailure, isTrue);
      expect(activeDownloads.canTryAnotherRelease, isFalse);
      expect(tooManyRequests.kind, RealDebridFailureKind.rateLimited);
      expect(tooManyRequests.canTryAnotherRelease, isFalse);
    });
  });

  group('Real-Debrid cached-preferred resolution', () {
    test(
      'plays an instantly cached torrent without reporting download work',
      () async {
        final client = _FakeRealDebridClient([
          _torrentInfo(status: 'waiting_files_selection'),
          _torrentInfo(
            status: 'downloaded',
            progress: 100,
            selected: true,
            links: const ['https://rd.example/episode-2'],
          ),
        ]);
        final resolver = RealDebridStreamResolver(
          client,
          const _ReleaseSource(),
          pollInterval: Duration.zero,
        );

        final states = await resolver.resolve(_episode).toList();

        expect(states, hasLength(1));
        expect(
          states.single,
          isA<StreamReady>()
              .having(
                (state) => state.debridService,
                'service',
                DebridService.realDebrid,
              )
              .having(
                (state) => state.uri,
                'URI',
                Uri.parse('https://cdn.example/episode.mkv'),
              ),
        );
        expect(client.selectedFileIds, [2]);
        expect(client.deletedTorrentIds, isEmpty);
        expect(client.unrestrictCalls, 1);
      },
    );

    test(
      'removes an uncached torrent as soon as it enters the queue',
      () async {
        final client = _FakeRealDebridClient([
          _torrentInfo(status: 'waiting_files_selection'),
          _torrentInfo(status: 'queued'),
        ]);
        final resolver = RealDebridStreamResolver(
          client,
          const _ReleaseSource(),
          pollInterval: Duration.zero,
        );

        await expectLater(
          resolver.resolve(_episode).drain<void>(),
          throwsA(
            isA<DebridCacheMissException>()
                .having(
                  (error) => error.service,
                  'service',
                  DebridService.realDebrid,
                )
                .having(
                  (error) => error.toString(),
                  'message',
                  allOf(contains('not ready'), contains('cancelled')),
                ),
          ),
        );

        expect(client.selectedFileIds, [2]);
        expect(client.deletedTorrentIds, ['torrent-id']);
        expect(client.unrestrictCalls, 0);
        expect(client.infoCalls, 2, reason: 'uncached work must not be polled');
      },
    );

    test(
      'selects files only once while Real-Debrid applies the selection',
      () async {
        final client = _FakeRealDebridClient([
          _torrentInfo(status: 'waiting_files_selection'),
          _torrentInfo(status: 'waiting_files_selection'),
          _torrentInfo(status: 'queued'),
        ]);
        final resolver = RealDebridStreamResolver(
          client,
          const _ReleaseSource(),
          pollInterval: Duration.zero,
        );

        await expectLater(
          resolver.resolve(_episode).drain<void>(),
          throwsA(isA<DebridCacheMissException>()),
        );

        expect(client.selectCalls, 1);
        expect(client.selectedFileIds, [2]);
        expect(client.deletedTorrentIds, ['torrent-id']);
      },
    );

    test(
      'cleanup failure is terminal and names the provider dashboard',
      () async {
        final client = _FakeRealDebridClient([
          _torrentInfo(status: 'waiting_files_selection'),
          _torrentInfo(status: 'downloading'),
        ], failDelete: true);
        final resolver = RealDebridStreamResolver(
          client,
          const _ReleaseSource(),
          pollInterval: Duration.zero,
        );

        await expectLater(
          resolver.resolve(_episode).drain<void>(),
          throwsA(
            isA<DebridCleanupFailureException>()
                .having(
                  (error) => error.service,
                  'service',
                  DebridService.realDebrid,
                )
                .having(
                  (error) => error.toString(),
                  'message',
                  allOf(
                    contains('Automatic failover stopped'),
                    contains('dashboard'),
                  ),
                ),
          ),
        );
        expect(client.deleteCalls, 1);
      },
    );
  });

  test('parses premium account state', () {
    final account = RealDebridAccount.fromJson({
      'id': 42,
      'username': 'tv-user',
      'type': 'premium',
      'expiration': DateTime.now()
          .add(const Duration(days: 10))
          .toUtc()
          .toIso8601String(),
    });

    expect(account.username, 'tv-user');
    expect(account.isPremium, isTrue);
  });
}

const _episode = EpisodeReference(
  anilistMediaId: 42,
  title: 'Example',
  episode: 2,
);

RealDebridTorrentInfo _torrentInfo({
  required String status,
  double progress = 0,
  bool selected = false,
  List<String> links = const [],
}) => RealDebridTorrentInfo(
  id: 'torrent-id',
  filename: 'Example batch',
  status: status,
  progress: progress,
  files: [
    RealDebridTorrentFile(
      id: 1,
      path: '/Example - 01.mkv',
      bytes: 1000,
      selected: selected,
    ),
    RealDebridTorrentFile(
      id: 2,
      path: '/Example - 02.mkv',
      bytes: 1100,
      selected: selected,
    ),
  ],
  links: links,
);

class _ReleaseSource implements ReleaseSource {
  const _ReleaseSource();

  @override
  String get id => 'test';

  @override
  Future<List<ReleaseCandidate>> search(
    EpisodeReference episode,
  ) async => const [
    ReleaseCandidate(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
      magnetUri: 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
      releaseName: 'Example batch',
      seeders: 100,
      sourceId: 'test',
      isBatch: true,
    ),
  ];
}

class _FakeRealDebridClient extends RealDebridClient {
  _FakeRealDebridClient(this.infos, {this.failDelete = false})
    : super(token: 'test');

  final List<RealDebridTorrentInfo> infos;
  final bool failDelete;
  final List<int> selectedFileIds = [];
  final List<String> deletedTorrentIds = [];
  int infoCalls = 0;
  int unrestrictCalls = 0;
  int deleteCalls = 0;
  int selectCalls = 0;

  @override
  Future<String> addMagnet(String magnetUri) async => 'torrent-id';

  @override
  Future<RealDebridTorrentInfo> torrentInfo(String id) async {
    final index = infoCalls.clamp(0, infos.length - 1);
    infoCalls++;
    return infos[index];
  }

  @override
  Future<void> selectFiles(String id, Iterable<int> fileIds) async {
    selectCalls++;
    selectedFileIds.addAll(fileIds);
  }

  @override
  Future<void> deleteTorrent(String id) async {
    deleteCalls++;
    if (failDelete) throw StateError('cleanup unavailable');
    deletedTorrentIds.add(id);
  }

  @override
  Future<RealDebridUnrestrictedLink> unrestrict(String link) async {
    unrestrictCalls++;
    return RealDebridUnrestrictedLink(
      download: Uri(scheme: 'https', host: 'cdn.example', path: '/episode.mkv'),
      filename: 'Example - 02.mkv',
    );
  }
}
