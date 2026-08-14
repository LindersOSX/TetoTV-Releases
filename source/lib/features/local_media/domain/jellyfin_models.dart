class JellyfinConnection {
  const JellyfinConnection({
    required this.baseUri,
    required this.serverName,
    required this.serverVersion,
    required this.userId,
    required this.username,
    required this.accessToken,
    required this.deviceId,
  });

  final Uri baseUri;
  final String serverName;
  final String serverVersion;
  final String userId;
  final String username;
  final String accessToken;
  final String deviceId;
}

class JellyfinServerInfo {
  const JellyfinServerInfo({
    required this.name,
    required this.version,
    required this.id,
  });

  final String name;
  final String version;
  final String id;
}

class JellyfinMediaItem {
  const JellyfinMediaItem({
    required this.id,
    required this.name,
    required this.type,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.runTimeTicks,
    this.primaryImageTag,
    this.mediaSourceId,
    this.container,
    this.overview,
  });

  final String id;
  final String name;
  final String type;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? runTimeTicks;
  final String? primaryImageTag;
  final String? mediaSourceId;
  final String? container;
  final String? overview;

  bool get isPlayable => const {'Movie', 'Episode', 'Video'}.contains(type);
  bool get isFolder => !isPlayable;

  String get displayTitle {
    if (type == 'Episode' && seriesName?.isNotEmpty == true) {
      final episode = episodeNumber == null
          ? ''
          : 'E${episodeNumber!.toString().padLeft(2, '0')} · ';
      return '$episode$name';
    }
    return name;
  }

  String get secondaryLabel {
    if (type == 'Episode') {
      final season = seasonNumber == null ? null : 'Season $seasonNumber';
      return [seriesName, season].whereType<String>().join(' · ');
    }
    return type;
  }
}

class JellyfinLibraryPage {
  const JellyfinLibraryPage({
    required this.items,
    required this.totalCount,
    required this.nextStartIndex,
  });

  final List<JellyfinMediaItem> items;
  final int totalCount;
  final int nextStartIndex;
}

class JellyfinException implements Exception {
  const JellyfinException(this.message);

  final String message;

  @override
  String toString() => message;
}
