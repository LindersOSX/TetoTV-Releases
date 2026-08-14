import 'dart:convert';

import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:sqflite/sqflite.dart';

class AddonStore {
  const AddonStore(this.database);

  final TetoTvDatabase database;

  Future<List<AddonRepository>> repositories() async {
    final db = await database.database;
    // Older private builds seeded a third-party catalog. Public builds never
    // ship, restore, or silently enable a source catalog. Remove only records
    // marked as the legacy app default; user-added repositories and explicitly
    // installed providers remain untouched.
    await db.transaction(removeLegacyDefaultRepositories);
    final rows = await db.query(
      'addon_repositories',
      orderBy: 'url COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => AddonRepository(
            url: row['url']! as String,
            enabled: row['enabled'] == 1,
            isDefault: row['is_default'] == 1,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row['updated_at']! as int,
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<void> saveRepository(AddonRepository repository) async {
    final db = await database.database;
    await db.insert('addon_repositories', {
      'url': repository.url,
      'enabled': repository.enabled ? 1 : 0,
      'is_default': repository.isDefault ? 1 : 0,
      'updated_at': repository.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeRepository(String url) async {
    final db = await database.database;
    await db.transaction((txn) async {
      await txn.delete(
        'addon_repositories',
        where: 'url = ?',
        whereArgs: [url],
      );
      await txn.delete(
        'marketplace_cache',
        where: 'repository_url = ?',
        whereArgs: [url],
      );
    });
  }

  Future<void> cacheCatalog(String repositoryUrl, String payload) async {
    final db = await database.database;
    await db.insert('marketplace_cache', {
      'repository_url': repositoryUrl,
      'payload_json': payload,
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> cachedCatalog(String repositoryUrl) async {
    final db = await database.database;
    final rows = await db.query(
      'marketplace_cache',
      columns: ['payload_json'],
      where: 'repository_url = ?',
      whereArgs: [repositoryUrl],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['payload_json'] as String?;
  }

  Future<List<InstalledStreamingAddon>> installedAddons() async {
    final db = await database.database;
    final rows = await db.query(
      'installed_addons',
      orderBy: 'id COLLATE NOCASE',
    );
    final result = <InstalledStreamingAddon>[];
    for (final row in rows) {
      try {
        result.add(InstalledStreamingAddon.fromRow(row));
      } on FormatException {
        // A malformed persisted addon is ignored instead of breaking Settings
        // or stream discovery. It can still be removed by reinstalling it.
      }
    }
    return result;
  }

  Future<void> install(InstalledStreamingAddon addon) async {
    final db = await database.database;
    await db.insert('installed_addons', {
      'id': addon.manifest.id,
      'manifest_json': jsonEncode(addon.manifest.toJson()),
      'payload': addon.payload,
      'enabled': addon.enabled ? 1 : 0,
      'repository_url': addon.manifest.repositoryUrl,
      'installed_at': addon.installedAt.millisecondsSinceEpoch,
      'updated_at': addon.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final db = await database.database;
    await db.update(
      'installed_addons',
      {
        'enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> uninstall(String id) async {
    final db = await database.database;
    await db.delete('installed_addons', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, ProviderHealth>> providerHealth() =>
      database.providerHealth();

  Future<void> recordProviderSuccess(String id) =>
      database.recordProviderSuccess(id);

  Future<ProviderHealth> recordProviderFailure(String id, Object error) =>
      database.recordProviderFailure(id, error);

  Future<void> clearProviderHealth(String id) =>
      database.clearProviderHealth(id);
}

/// Removes only repositories marked by an older app build as app-provided.
///
/// The public build does not retain the retired URL (even as a migration
/// string). The `is_default` bit was never user-settable, so it uniquely
/// identifies the old seeded record without deleting user-added repositories
/// or anything from `installed_addons`.
Future<void> removeLegacyDefaultRepositories(DatabaseExecutor database) async {
  final legacyDefaults = await database.query(
    'addon_repositories',
    columns: ['url'],
    where: 'is_default = 1',
  );
  for (final row in legacyDefaults) {
    final url = row['url'] as String?;
    if (url == null) continue;
    await database.delete(
      'marketplace_cache',
      where: 'repository_url = ?',
      whereArgs: [url],
    );
  }
  await database.delete('addon_repositories', where: 'is_default = 1');
}
