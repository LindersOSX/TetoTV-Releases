import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<void> configureTetoTvDatabase(Database db) async {
  // journal_mode returns a result row on Android, so sqflite requires
  // rawQuery rather than execute.
  await db.rawQuery('PRAGMA journal_mode=WAL');
  await db.execute('PRAGMA foreign_keys=ON');
}

class PlaybackCheckpoint {
  const PlaybackCheckpoint({
    required this.anilistMediaId,
    required this.episode,
    required this.title,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.malMediaId,
    this.coverImageUrl,
    this.completed = false,
  });

  final int anilistMediaId;
  final int? malMediaId;
  final int episode;
  final String title;
  final String? coverImageUrl;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;
  final bool completed;

  double get progress => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);

  Map<String, Object?> toMap() => {
    'anilist_media_id': anilistMediaId,
    'mal_media_id': malMediaId,
    'episode': episode,
    'title': title,
    'cover_image_url': coverImageUrl,
    'position_ms': position.inMilliseconds,
    'duration_ms': duration.inMilliseconds,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'completed': completed ? 1 : 0,
  };

  factory PlaybackCheckpoint.fromMap(Map<String, Object?> value) =>
      PlaybackCheckpoint(
        anilistMediaId: value['anilist_media_id']! as int,
        malMediaId: value['mal_media_id'] as int?,
        episode: value['episode']! as int,
        title: value['title']! as String,
        coverImageUrl: value['cover_image_url'] as String?,
        position: Duration(milliseconds: value['position_ms']! as int),
        duration: Duration(milliseconds: value['duration_ms']! as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          value['updated_at']! as int,
        ),
        completed: value['completed'] == 1,
      );
}

class SeriesPlaybackPreferences {
  const SeriesPlaybackPreferences({
    this.audioLanguage = 'eng',
    this.audioPreferenceSet = false,
    this.subtitleLanguage = 'eng',
    this.subtitleEnabled = true,
    this.subtitlePreferenceSet = false,
    this.subtitleSize = 34,
    this.subtitlePosition = 100,
    this.subtitleDelayMs = 0,
    this.audioDelayMs = 0,
    this.decoder = 'hardware-safe',
    this.videoFit = 'contain',
    this.highContrastSubtitles = false,
    this.autoplayNextEpisode = true,
    this.skipFillerEpisodes = false,
    this.preferredStreamLanguage = 'dub',
    this.preferredQuality = 'any',
    this.preferredCodec = 'any',
    this.preferredHdrMode = 'any',
    this.allowBatchStreams = true,
    this.streamSortMode = 'compatibility',
    this.preferredReleaseProvider,
    this.preferredReleaseGroup,
  });

  final String audioLanguage;
  final bool audioPreferenceSet;
  final String subtitleLanguage;
  final bool subtitleEnabled;
  final bool subtitlePreferenceSet;
  final double subtitleSize;
  final int subtitlePosition;
  final int subtitleDelayMs;
  final int audioDelayMs;
  final String decoder;
  final String videoFit;
  final bool highContrastSubtitles;
  final bool autoplayNextEpisode;
  final bool skipFillerEpisodes;
  final String preferredStreamLanguage;
  final String preferredQuality;
  final String preferredCodec;
  final String preferredHdrMode;
  final bool allowBatchStreams;
  final String streamSortMode;
  final String? preferredReleaseProvider;
  final String? preferredReleaseGroup;

  SeriesPlaybackPreferences copyWith({
    String? audioLanguage,
    bool? audioPreferenceSet,
    String? subtitleLanguage,
    bool? subtitleEnabled,
    bool? subtitlePreferenceSet,
    double? subtitleSize,
    int? subtitlePosition,
    int? subtitleDelayMs,
    int? audioDelayMs,
    String? decoder,
    String? videoFit,
    bool? highContrastSubtitles,
    bool? autoplayNextEpisode,
    bool? skipFillerEpisodes,
    String? preferredStreamLanguage,
    String? preferredQuality,
    String? preferredCodec,
    String? preferredHdrMode,
    bool? allowBatchStreams,
    String? streamSortMode,
    String? preferredReleaseProvider,
    bool clearPreferredReleaseProvider = false,
    String? preferredReleaseGroup,
    bool clearPreferredReleaseGroup = false,
  }) => SeriesPlaybackPreferences(
    audioLanguage: audioLanguage ?? this.audioLanguage,
    audioPreferenceSet: audioPreferenceSet ?? this.audioPreferenceSet,
    subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
    subtitleEnabled: subtitleEnabled ?? this.subtitleEnabled,
    subtitlePreferenceSet: subtitlePreferenceSet ?? this.subtitlePreferenceSet,
    subtitleSize: subtitleSize ?? this.subtitleSize,
    subtitlePosition: subtitlePosition ?? this.subtitlePosition,
    subtitleDelayMs: subtitleDelayMs ?? this.subtitleDelayMs,
    audioDelayMs: audioDelayMs ?? this.audioDelayMs,
    decoder: decoder ?? this.decoder,
    videoFit: videoFit ?? this.videoFit,
    highContrastSubtitles: highContrastSubtitles ?? this.highContrastSubtitles,
    autoplayNextEpisode: autoplayNextEpisode ?? this.autoplayNextEpisode,
    skipFillerEpisodes: skipFillerEpisodes ?? this.skipFillerEpisodes,
    preferredStreamLanguage:
        preferredStreamLanguage ?? this.preferredStreamLanguage,
    preferredQuality: preferredQuality ?? this.preferredQuality,
    preferredCodec: preferredCodec ?? this.preferredCodec,
    preferredHdrMode: preferredHdrMode ?? this.preferredHdrMode,
    allowBatchStreams: allowBatchStreams ?? this.allowBatchStreams,
    streamSortMode: streamSortMode ?? this.streamSortMode,
    preferredReleaseProvider: clearPreferredReleaseProvider
        ? null
        : preferredReleaseProvider ?? this.preferredReleaseProvider,
    preferredReleaseGroup: clearPreferredReleaseGroup
        ? null
        : preferredReleaseGroup ?? this.preferredReleaseGroup,
  );

  Map<String, Object?> toJson() => {
    'audioLanguage': audioLanguage,
    'audioPreferenceSet': audioPreferenceSet,
    'subtitleLanguage': subtitleLanguage,
    'subtitleEnabled': subtitleEnabled,
    'subtitlePreferenceSet': subtitlePreferenceSet,
    'subtitleSize': subtitleSize,
    'subtitlePosition': subtitlePosition,
    'subtitleDelayMs': subtitleDelayMs,
    'audioDelayMs': audioDelayMs,
    'decoder': decoder,
    'videoFit': videoFit,
    'highContrastSubtitles': highContrastSubtitles,
    'autoplayNextEpisode': autoplayNextEpisode,
    'skipFillerEpisodes': skipFillerEpisodes,
    'preferredStreamLanguage': preferredStreamLanguage,
    'preferredQuality': preferredQuality,
    'preferredCodec': preferredCodec,
    'preferredHdrMode': preferredHdrMode,
    'allowBatchStreams': allowBatchStreams,
    'streamSortMode': streamSortMode,
    'preferredReleaseProvider': preferredReleaseProvider,
    'preferredReleaseGroup': preferredReleaseGroup,
  };

  factory SeriesPlaybackPreferences.fromJson(Map<String, dynamic> json) =>
      SeriesPlaybackPreferences(
        audioLanguage: json['audioLanguage'] as String? ?? 'eng',
        audioPreferenceSet: json['audioPreferenceSet'] as bool? ?? false,
        subtitleLanguage: json['subtitleLanguage'] as String? ?? 'eng',
        subtitleEnabled: json['subtitleEnabled'] as bool? ?? true,
        subtitlePreferenceSet: json['subtitlePreferenceSet'] as bool? ?? false,
        subtitleSize: (json['subtitleSize'] as num?)?.toDouble() ?? 34,
        subtitlePosition: json['subtitlePosition'] as int? ?? 100,
        subtitleDelayMs: json['subtitleDelayMs'] as int? ?? 0,
        audioDelayMs: json['audioDelayMs'] as int? ?? 0,
        decoder: json['decoder'] as String? ?? 'hardware-safe',
        videoFit: json['videoFit'] as String? ?? 'contain',
        highContrastSubtitles: json['highContrastSubtitles'] as bool? ?? false,
        autoplayNextEpisode: json['autoplayNextEpisode'] as bool? ?? true,
        skipFillerEpisodes: json['skipFillerEpisodes'] as bool? ?? false,
        preferredStreamLanguage:
            json['preferredStreamLanguage'] as String? ?? 'dub',
        preferredQuality: json['preferredQuality'] as String? ?? 'any',
        preferredCodec: json['preferredCodec'] as String? ?? 'any',
        preferredHdrMode: json['preferredHdrMode'] as String? ?? 'any',
        allowBatchStreams: json['allowBatchStreams'] as bool? ?? true,
        streamSortMode: json['streamSortMode'] as String? ?? 'compatibility',
        preferredReleaseProvider: json['preferredReleaseProvider'] as String?,
        preferredReleaseGroup: json['preferredReleaseGroup'] as String?,
      );
}

class ProviderHealth {
  const ProviderHealth({
    required this.providerId,
    this.consecutiveFailures = 0,
    this.totalFailures = 0,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastError,
    this.quarantinedUntil,
  });

  final String providerId;
  final int consecutiveFailures;
  final int totalFailures;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final String? lastError;
  final DateTime? quarantinedUntil;

  bool get isQuarantined => quarantinedUntil?.isAfter(DateTime.now()) ?? false;

  factory ProviderHealth.fromMap(Map<String, Object?> row) => ProviderHealth(
    providerId: row['provider_id']! as String,
    consecutiveFailures: row['consecutive_failures']! as int,
    totalFailures: row['total_failures']! as int,
    lastSuccessAt: _dateFromMilliseconds(row['last_success_at']),
    lastFailureAt: _dateFromMilliseconds(row['last_failure_at']),
    lastError: row['last_error'] as String?,
    quarantinedUntil: _dateFromMilliseconds(row['quarantined_until']),
  );
}

class DevicePlaybackProfile {
  const DevicePlaybackProfile({
    required this.deviceKey,
    this.preferredEngine = 'auto',
    this.media3Failures = 0,
    this.mpvFailures = 0,
    this.vlcFailures = 0,
  });

  final String deviceKey;
  final String preferredEngine;
  final int media3Failures;
  final int mpvFailures;
  final int vlcFailures;

  factory DevicePlaybackProfile.fromMap(Map<String, Object?> row) =>
      DevicePlaybackProfile(
        deviceKey: row['device_key']! as String,
        preferredEngine: row['preferred_engine']! as String,
        media3Failures: row['media3_failures']! as int,
        mpvFailures: row['mpv_failures']! as int,
        vlcFailures: row['vlc_failures']! as int,
      );
}

DateTime? _dateFromMilliseconds(Object? value) =>
    value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

class TetoTvDatabase {
  TetoTvDatabase._();

  static final instance = TetoTvDatabase._();
  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database async {
    final openDatabase = _database;
    if (openDatabase != null) return openDatabase;

    // Several providers can request the database during the same frame. Keep
    // one shared open operation so Android never races multiple connections to
    // the same file.
    final opening = _opening ??= _open();
    try {
      final database = await opening;
      _database = database;
      return database;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    return openDatabase(
      path.join(root, 'tetotv.db'),
      version: 4,
      onConfigure: configureTetoTvDatabase,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE playback_history (
            anilist_media_id INTEGER NOT NULL,
            mal_media_id INTEGER,
            episode INTEGER NOT NULL,
            title TEXT NOT NULL,
            cover_image_url TEXT,
            position_ms INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            completed INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (anilist_media_id, episode)
          )
        ''');
        await db.execute('''
          CREATE INDEX playback_history_updated
          ON playback_history(updated_at DESC)
        ''');
        await db.execute('''
          CREATE TABLE series_preferences (
            anilist_media_id INTEGER PRIMARY KEY,
            preferences_json TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE stream_failures (
            device_key TEXT NOT NULL,
            info_hash TEXT NOT NULL,
            reason TEXT,
            failure_count INTEGER NOT NULL DEFAULT 1,
            last_failed_at INTEGER NOT NULL,
            PRIMARY KEY (device_key, info_hash)
          )
        ''');
        await db.execute('''
          CREATE TABLE catalog_cache (
            cache_key TEXT PRIMARY KEY,
            payload_json TEXT NOT NULL,
            expires_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE performance_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            duration_us INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await _createContinueDismissalsTable(db);
        await _createAddonTables(db);
        await _createReliabilityTables(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createContinueDismissalsTable(db);
        if (oldVersion < 3) await _createAddonTables(db);
        if (oldVersion < 4) await _createReliabilityTables(db);
      },
    );
  }

  Future<void> saveCheckpoint(PlaybackCheckpoint checkpoint) async {
    final db = await database;
    await db.transaction((txn) => saveCheckpointTransaction(txn, checkpoint));
  }

  Future<PlaybackCheckpoint?> checkpoint(int mediaId, int episode) async {
    final db = await database;
    final rows = await db.query(
      'playback_history',
      where: 'anilist_media_id = ? AND episode = ?',
      whereArgs: [mediaId, episode],
      limit: 1,
    );
    return rows.isEmpty ? null : PlaybackCheckpoint.fromMap(rows.first);
  }

  Future<PlaybackCheckpoint?> latestCheckpoint(int mediaId) async {
    final db = await database;
    final rows = await db.query(
      'playback_history',
      where: 'anilist_media_id = ?',
      whereArgs: [mediaId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : PlaybackCheckpoint.fromMap(rows.first);
  }

  Future<List<PlaybackCheckpoint>> recentHistory({int limit = 20}) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT h.* FROM playback_history h
      INNER JOIN (
        SELECT anilist_media_id, MAX(updated_at) AS latest
        FROM playback_history
        GROUP BY anilist_media_id
      ) grouped
      ON h.anilist_media_id = grouped.anilist_media_id
      AND h.updated_at = grouped.latest
      ORDER BY h.updated_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(PlaybackCheckpoint.fromMap).toList(growable: false);
  }

  Future<void> removeLocalHistory(int mediaId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'playback_history',
        where: 'anilist_media_id = ?',
        whereArgs: [mediaId],
      );
      await txn.insert(
        'continue_watching_dismissals',
        {
          'anilist_media_id': mediaId,
          'dismissed_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<Set<int>> dismissedContinueWatchingIds() async {
    final db = await database;
    final rows = await db.query(
      'continue_watching_dismissals',
      columns: ['anilist_media_id'],
    );
    return rows.map((row) => row['anilist_media_id']! as int).toSet();
  }

  Future<SeriesPlaybackPreferences> seriesPreferences(int mediaId) async {
    final db = await database;
    final rows = await db.query(
      'series_preferences',
      columns: ['preferences_json'],
      where: 'anilist_media_id = ?',
      whereArgs: [mediaId],
      limit: 1,
    );
    if (rows.isEmpty) return const SeriesPlaybackPreferences();
    return SeriesPlaybackPreferences.fromJson(
      jsonDecode(rows.first['preferences_json']! as String)
          as Map<String, dynamic>,
    );
  }

  Future<void> saveSeriesPreferences(
    int mediaId,
    SeriesPlaybackPreferences preferences,
  ) async {
    final db = await database;
    await db.insert('series_preferences', {
      'anilist_media_id': mediaId,
      'preferences_json': jsonEncode(preferences.toJson()),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> recordStreamFailure({
    required String deviceKey,
    required String infoHash,
    required String reason,
  }) async {
    final db = await database;
    await db.rawInsert(
      '''
      INSERT INTO stream_failures
        (device_key, info_hash, reason, failure_count, last_failed_at)
      VALUES (?, ?, ?, 1, ?)
      ON CONFLICT(device_key, info_hash) DO UPDATE SET
        reason = excluded.reason,
        failure_count = failure_count + 1,
        last_failed_at = excluded.last_failed_at
      ''',
      [
        deviceKey,
        infoHash.toLowerCase(),
        redactDiagnosticValue(reason),
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<Map<String, int>> failureCounts(String deviceKey) async {
    final db = await database;
    final rows = await db.query(
      'stream_failures',
      columns: ['info_hash', 'failure_count'],
      where: 'device_key = ?',
      whereArgs: [deviceKey],
    );
    return {
      for (final row in rows)
        row['info_hash']! as String: row['failure_count']! as int,
    };
  }

  Future<void> recordPerformance(String name, Duration duration) async {
    final db = await database;
    await db.insert('performance_events', {
      'name': name,
      'duration_us': duration.inMicroseconds,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await db.delete(
      'performance_events',
      where:
          'id NOT IN (SELECT id FROM performance_events ORDER BY id DESC LIMIT 500)',
    );
  }

  Future<Map<String, ProviderHealth>> providerHealth() async {
    final db = await database;
    final rows = await db.query('provider_health');
    return {
      for (final row in rows)
        row['provider_id']! as String: ProviderHealth.fromMap(row),
    };
  }

  Future<void> recordProviderSuccess(String providerId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawInsert(
      '''
      INSERT INTO provider_health
        (provider_id, consecutive_failures, total_failures, last_success_at,
         last_error, quarantined_until)
      VALUES (?, 0, 0, ?, NULL, NULL)
      ON CONFLICT(provider_id) DO UPDATE SET
        consecutive_failures = 0,
        last_success_at = excluded.last_success_at,
        last_error = NULL,
        quarantined_until = NULL
      ''',
      [providerId, now],
    );
  }

  Future<ProviderHealth> recordProviderFailure(
    String providerId,
    Object error, {
    int quarantineAfter = 3,
    Duration quarantineFor = const Duration(minutes: 30),
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'provider_health',
        where: 'provider_id = ?',
        whereArgs: [providerId],
        limit: 1,
      );
      final previous = rows.isEmpty
          ? ProviderHealth(providerId: providerId)
          : ProviderHealth.fromMap(rows.first);
      final failures = previous.consecutiveFailures + 1;
      final now = DateTime.now();
      final quarantine = failures >= quarantineAfter
          ? now.add(quarantineFor)
          : null;
      final message = redactDiagnosticValue(error.toString(), maximum: 300);
      await txn.insert('provider_health', {
        'provider_id': providerId,
        'consecutive_failures': failures,
        'total_failures': previous.totalFailures + 1,
        'last_success_at': previous.lastSuccessAt?.millisecondsSinceEpoch,
        'last_failure_at': now.millisecondsSinceEpoch,
        'last_error': message,
        'quarantined_until': quarantine?.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return ProviderHealth(
        providerId: providerId,
        consecutiveFailures: failures,
        totalFailures: previous.totalFailures + 1,
        lastSuccessAt: previous.lastSuccessAt,
        lastFailureAt: now,
        lastError: message,
        quarantinedUntil: quarantine,
      );
    });
  }

  Future<void> clearProviderHealth(String providerId) async {
    final db = await database;
    await db.delete(
      'provider_health',
      where: 'provider_id = ?',
      whereArgs: [providerId],
    );
  }

  Future<DevicePlaybackProfile> devicePlaybackProfile(String deviceKey) async {
    final db = await database;
    final rows = await db.query(
      'device_player_profiles',
      where: 'device_key = ?',
      whereArgs: [deviceKey],
      limit: 1,
    );
    return rows.isEmpty
        ? DevicePlaybackProfile(deviceKey: deviceKey)
        : DevicePlaybackProfile.fromMap(rows.first);
  }

  Future<DevicePlaybackProfile> recordPlayerFailure(
    String deviceKey,
    String engine,
  ) async {
    final current = await devicePlaybackProfile(deviceKey);
    var media3 = current.media3Failures;
    var mpv = current.mpvFailures;
    var vlc = current.vlcFailures;
    if (engine == 'media3') media3++;
    if (engine == 'mpv') mpv++;
    if (engine == 'vlc') vlc++;
    final preferred = mpv >= 2
        ? 'vlc'
        : media3 >= 2
        ? 'mpv'
        : current.preferredEngine;
    final next = DevicePlaybackProfile(
      deviceKey: deviceKey,
      preferredEngine: preferred,
      media3Failures: media3,
      mpvFailures: mpv,
      vlcFailures: vlc,
    );
    await _saveDevicePlaybackProfile(next);
    return next;
  }

  Future<void> recordPlayerSuccess(String deviceKey, String engine) async {
    final current = await devicePlaybackProfile(deviceKey);
    await _saveDevicePlaybackProfile(
      DevicePlaybackProfile(
        deviceKey: deviceKey,
        preferredEngine: engine,
        media3Failures: engine == 'media3' ? 0 : current.media3Failures,
        mpvFailures: engine == 'mpv' ? 0 : current.mpvFailures,
        vlcFailures: engine == 'vlc' ? 0 : current.vlcFailures,
      ),
    );
  }

  Future<void> setPreferredPlayer(String deviceKey, String engine) async {
    final current = await devicePlaybackProfile(deviceKey);
    await _saveDevicePlaybackProfile(
      DevicePlaybackProfile(
        deviceKey: deviceKey,
        preferredEngine: engine,
        media3Failures: current.media3Failures,
        mpvFailures: current.mpvFailures,
        vlcFailures: current.vlcFailures,
      ),
    );
  }

  Future<void> _saveDevicePlaybackProfile(DevicePlaybackProfile profile) async {
    final db = await database;
    await db.insert('device_player_profiles', {
      'device_key': profile.deviceKey,
      'preferred_engine': profile.preferredEngine,
      'media3_failures': profile.media3Failures,
      'mpv_failures': profile.mpvFailures,
      'vlc_failures': profile.vlcFailures,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> recordDiagnosticEvent({
    required String category,
    required Object message,
    Object? details,
  }) async {
    try {
      final db = await database;
      await db.insert('diagnostic_events', {
        'category': redactDiagnosticValue(category, maximum: 48),
        'message': redactDiagnosticValue(message.toString(), maximum: 500),
        'details_json': details == null
            ? null
            : redactDiagnosticValue(
                details is String ? details : jsonEncode(details),
                maximum: 2000,
              ),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await db.delete(
        'diagnostic_events',
        where:
            'id NOT IN (SELECT id FROM diagnostic_events ORDER BY id DESC LIMIT 100)',
      );
    } catch (_) {
      // Diagnostics must never become another app failure.
    }
  }

  Future<void> cacheJson(
    String key,
    Map<String, dynamic> payload, {
    Duration maxAge = const Duration(minutes: 30),
  }) async {
    final db = await database;
    final now = DateTime.now();
    await db.insert('catalog_cache', {
      'cache_key': key,
      'payload_json': jsonEncode(payload),
      'expires_at': now.add(maxAge).millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> cachedJson(
    String key, {
    bool allowExpired = false,
  }) async {
    final db = await database;
    final rows = await db.query(
      'catalog_cache',
      where: allowExpired
          ? 'cache_key = ?'
          : 'cache_key = ? AND expires_at > ?',
      whereArgs: allowExpired
          ? [key]
          : [key, DateTime.now().millisecondsSinceEpoch],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['payload_json']! as String)
        as Map<String, dynamic>;
  }

  Future<Map<String, Object?>> diagnosticsSnapshot() async {
    final db = await database;
    final playback = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM playback_history'),
    );
    final failures = await db.rawQuery('''
      SELECT reason, failure_count, last_failed_at
      FROM stream_failures ORDER BY last_failed_at DESC LIMIT 25
    ''');
    final timings = await db.rawQuery('''
      SELECT name, duration_us, created_at
      FROM performance_events ORDER BY created_at DESC LIMIT 100
    ''');
    final events = await db.rawQuery('''
      SELECT category, message, details_json, created_at
      FROM diagnostic_events ORDER BY created_at DESC LIMIT 100
    ''');
    final providers = await db.rawQuery('''
      SELECT provider_id, consecutive_failures, total_failures,
             last_success_at, last_failure_at, last_error, quarantined_until
      FROM provider_health ORDER BY provider_id
    ''');
    final playerProfiles = await db.rawQuery('''
      SELECT device_key, preferred_engine, media3_failures, mpv_failures,
             vlc_failures, updated_at FROM device_player_profiles
    ''');
    return {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'playbackEntryCount': playback ?? 0,
      'recentStreamFailures': [
        for (final row in failures)
          {
            ...row,
            if (row['reason'] case final String reason)
              'reason': redactDiagnosticValue(reason),
          },
      ],
      'recentFrameTimings': timings,
      // Redact again at the export boundary. This also protects reports that
      // include rows written by an older app build with narrower rules.
      'diagnosticEvents': [
        for (final row in events)
          {
            ...row,
            if (row['category'] case final String value)
              'category': redactDiagnosticValue(value, maximum: 48),
            if (row['message'] case final String value)
              'message': redactDiagnosticValue(value, maximum: 500),
            if (row['details_json'] case final String value)
              'details_json': redactDiagnosticValue(value, maximum: 2000),
          },
      ],
      'providerHealth': [
        for (final row in providers)
          {
            ...row,
            if (row['provider_id'] case final String value)
              'provider_id': redactDiagnosticValue(value, maximum: 120),
            if (row['last_error'] case final String value)
              'last_error': redactDiagnosticValue(value, maximum: 300),
          },
      ],
      'devicePlayerProfiles': playerProfiles,
    };
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _opening = null;
  }
}

Future<void> _createAddonTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS addon_repositories (
      url TEXT PRIMARY KEY,
      enabled INTEGER NOT NULL DEFAULT 1,
      is_default INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS installed_addons (
      id TEXT PRIMARY KEY,
      manifest_json TEXT NOT NULL,
      payload TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1,
      repository_url TEXT NOT NULL,
      installed_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS marketplace_cache (
      repository_url TEXT PRIMARY KEY,
      payload_json TEXT NOT NULL,
      fetched_at INTEGER NOT NULL
    )
  ''');
}

Future<void> _createReliabilityTables(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS provider_health (
      provider_id TEXT PRIMARY KEY,
      consecutive_failures INTEGER NOT NULL DEFAULT 0,
      total_failures INTEGER NOT NULL DEFAULT 0,
      last_success_at INTEGER,
      last_failure_at INTEGER,
      last_error TEXT,
      quarantined_until INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS device_player_profiles (
      device_key TEXT PRIMARY KEY,
      preferred_engine TEXT NOT NULL DEFAULT 'auto',
      media3_failures INTEGER NOT NULL DEFAULT 0,
      mpv_failures INTEGER NOT NULL DEFAULT 0,
      vlc_failures INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS diagnostic_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL,
      message TEXT NOT NULL,
      details_json TEXT,
      created_at INTEGER NOT NULL
    )
  ''');
}

String redactDiagnosticValue(String value, {int maximum = 500}) {
  var redacted = value
      .replaceAll(
        RegExp(r'''https?://[^\s"']+''', caseSensitive: false),
        '[URL]',
      )
      .replaceAll(
        RegExp(r'''magnet:\?[^\s"']+''', caseSensitive: false),
        '[MAGNET]',
      )
      .replaceAll(
        RegExp(
          r'''\b(?![A-Za-z]:[\\/])[A-Za-z][A-Za-z0-9+.-]{0,31}:(?![0-9\s])[^\s"'<>]+''',
          caseSensitive: false,
        ),
        '[URI]',
      )
      .replaceAllMapped(
        RegExp(
          r'''(^|[\s"'(=\[])(?:[A-Za-z]:[\\/]|\\\\[^\\/\s"'<>]+[\\/])[^\r\n"'<>]*''',
          multiLine: true,
        ),
        (match) => '${match.group(1)}[PATH]',
      )
      .replaceAllMapped(
        RegExp(r'''(^|[\s"'(=\[])/(?!/)[^\r\n"'<>]*''', multiLine: true),
        (match) => '${match.group(1)}[PATH]',
      )
      .replaceAll(
        RegExp(r'\bgithub_pat_[A-Za-z0-9_]+\b', caseSensitive: false),
        '[REDACTED]',
      )
      .replaceAll(
        RegExp(r'\bgh[pousr]_[A-Za-z0-9]{20,}\b', caseSensitive: false),
        '[REDACTED]',
      )
      .replaceAll(
        RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
        '[REDACTED]',
      )
      .replaceAll(
        RegExp(r'\bbearer\s+[^\s,;"\x27]+', caseSensitive: false),
        'Bearer [REDACTED]',
      )
      .replaceAll(
        RegExp(
          r'''(["']?(?:authorization|access[_ -]?token|refresh[_ -]?token|token|api[_ -]?key|client[_ -]?secret|password)["']?\s*[:=]\s*["']?)[^\s,;"']+''',
          caseSensitive: false,
        ),
        '[REDACTED]',
      )
      .replaceAll(RegExp(r'\b[a-fA-F0-9]{40,}\b'), '[INFO_HASH]')
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .trim();
  if (redacted.length > maximum) redacted = redacted.substring(0, maximum);
  return redacted;
}

Future<void> saveCheckpointTransaction(
  DatabaseExecutor database,
  PlaybackCheckpoint checkpoint,
) async {
  final existing = await database.query(
    'playback_history',
    columns: const ['updated_at'],
    where: 'anilist_media_id = ? AND episode = ?',
    whereArgs: [checkpoint.anilistMediaId, checkpoint.episode],
    limit: 1,
  );
  final existingUpdatedAt = existing.isEmpty
      ? null
      : existing.first['updated_at'] as int?;
  // Position callbacks and route disposal can enqueue overlapping writes.
  // Never let an older, slower write overwrite the final Exit checkpoint.
  if (existingUpdatedAt != null &&
      existingUpdatedAt > checkpoint.updatedAt.millisecondsSinceEpoch) {
    return;
  }
  await database.delete(
    'continue_watching_dismissals',
    where: 'anilist_media_id = ?',
    whereArgs: [checkpoint.anilistMediaId],
  );
  await database.insert(
    'playback_history',
    checkpoint.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _createContinueDismissalsTable(DatabaseExecutor db) =>
    db.execute('''
  CREATE TABLE IF NOT EXISTS continue_watching_dismissals (
    anilist_media_id INTEGER PRIMARY KEY,
    dismissed_at INTEGER NOT NULL
  )
''');
