import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../audio/audio_project.dart';
import '../util/json_util.dart';
import '../video/model.dart';
import 'asset.dart';

/// Current version of the `.wojanmedia` project format.
const int kProjectFormatVersion = 2;

enum ProjectType { audio, video, musicVideo, lyric, karaoke, visualizer }

enum RenderStatus { none, queued, rendering, done, failed }
enum PublishStatus { draft, ready, pending, uploading, handedOff, uploaded, scheduled, published, error, needsApproval }

/// Publication draft attached to a project (synchronised).
class PublishDraft {
  String title, description;
  List<String> hashtags;
  List<String> platforms;
  String visibility; // private / unlisted / public
  DateTime? scheduledAt;
  PublishDraft({this.title = '', this.description = '', List<String>? hashtags, List<String>? platforms, this.visibility = 'private', this.scheduledAt})
      : hashtags = hashtags ?? [],
        platforms = platforms ?? [];
  Map<String, dynamic> toJson() => {'title': title, 'description': description, 'hashtags': hashtags, 'platforms': platforms, 'visibility': visibility, 'scheduledAt': scheduledAt?.toIso8601String()};
  factory PublishDraft.fromJson(Map<String, dynamic> j) => PublishDraft(
        title: js(j['title']),
        description: js(j['description']),
        hashtags: (j['hashtags'] as List?)?.map((e) => '$e').toList(),
        platforms: (j['platforms'] as List?)?.map((e) => '$e').toList(),
        visibility: js(j['visibility'], 'private'),
        scheduledAt: j['scheduledAt'] == null ? null : DateTime.tryParse('${j['scheduledAt']}'),
      );
}

/// The complete, portable project document.
class ProjectDoc {
  String id;
  String name;
  ProjectType type;
  DateTime created, modified;
  String revision; // unique id of this saved state
  String? parentRevision; // revision this one was derived from (for conflicts)
  List<String> ancestors; // recent ancestor revisions (newest last), for sync
  bool deleted; // tombstone (permanently deleted on some device)
  String deviceId;
  String category;
  List<String> tags;
  bool favorite, archived, trashed;
  DateTime? trashedAt;
  AudioProject? audio;
  VideoProject? video;
  Map<String, MediaAsset> assets;
  PublishDraft publish;
  RenderStatus renderStatus;
  PublishStatus publishStatus;
  Map<String, dynamic> exportSettings;
  Map<String, dynamic> extra; // forward-compatible bag (style id, lyrics source …)

  ProjectDoc({
    String? id,
    required this.name,
    required this.type,
    DateTime? created,
    DateTime? modified,
    String? revision,
    this.parentRevision,
    List<String>? ancestors,
    this.deleted = false,
    this.deviceId = '',
    this.category = '',
    List<String>? tags,
    this.favorite = false,
    this.archived = false,
    this.trashed = false,
    this.trashedAt,
    this.audio,
    this.video,
    Map<String, MediaAsset>? assets,
    PublishDraft? publish,
    this.renderStatus = RenderStatus.none,
    this.publishStatus = PublishStatus.draft,
    Map<String, dynamic>? exportSettings,
    Map<String, dynamic>? extra,
  })  : id = id ?? const Uuid().v4(),
        created = created ?? DateTime.now().toUtc(),
        modified = modified ?? DateTime.now().toUtc(),
        revision = revision ?? const Uuid().v4(),
        tags = tags ?? [],
        ancestors = ancestors ?? [],
        assets = assets ?? {},
        publish = publish ?? PublishDraft(),
        exportSettings = exportSettings ?? {},
        extra = extra ?? {};

  double get duration => video?.duration ?? audio?.duration ?? 0;

  Map<String, dynamic> toJson() => {
        'format': 'wojanmedia',
        'version': kProjectFormatVersion,
        'id': id,
        'name': name,
        'type': type.name,
        'created': created.toIso8601String(),
        'modified': modified.toIso8601String(),
        'revision': revision,
        'parentRevision': parentRevision,
        'ancestors': ancestors,
        'deleted': deleted,
        'deviceId': deviceId,
        'category': category,
        'tags': tags,
        'favorite': favorite,
        'archived': archived,
        'trashed': trashed,
        'trashedAt': trashedAt?.toIso8601String(),
        'audio': audio?.toJson(),
        'video': video?.toJson(),
        'assets': assets.values.map((a) => a.toJson()).toList(),
        'publish': publish.toJson(),
        'renderStatus': renderStatus.name,
        'publishStatus': publishStatus.name,
        'exportSettings': exportSettings,
        'extra': extra,
      };

  factory ProjectDoc.fromJson(Map<String, dynamic> raw) {
    final j = migrateProjectJson(raw);
    return ProjectDoc(
      id: js(j['id']),
      name: js(j['name'], 'Projekt'),
      type: ProjectType.values.firstWhere((e) => e.name == j['type'], orElse: () => ProjectType.video),
      created: DateTime.tryParse(js(j['created'])) ?? DateTime.now().toUtc(),
      modified: DateTime.tryParse(js(j['modified'])) ?? DateTime.now().toUtc(),
      revision: js(j['revision']),
      parentRevision: j['parentRevision'] as String?,
      ancestors: (j['ancestors'] as List?)?.map((e) => '$e').toList(),
      deleted: jb(j['deleted']),
      deviceId: js(j['deviceId']),
      category: js(j['category']),
      tags: (j['tags'] as List?)?.map((e) => '$e').toList(),
      favorite: jb(j['favorite']),
      archived: jb(j['archived']),
      trashed: jb(j['trashed']),
      trashedAt: j['trashedAt'] == null ? null : DateTime.tryParse('${j['trashedAt']}'),
      audio: j['audio'] == null ? null : AudioProject.fromJson(jm(j['audio'])),
      video: j['video'] == null ? null : VideoProject.fromJson(jm(j['video'])),
      assets: {for (final a in jl(j['assets']).map(MediaAsset.fromJson)) a.id: a},
      publish: PublishDraft.fromJson(jm(j['publish'])),
      renderStatus: RenderStatus.values.firstWhere((e) => e.name == j['renderStatus'], orElse: () => RenderStatus.none),
      publishStatus: PublishStatus.values.firstWhere((e) => e.name == j['publishStatus'], orElse: () => PublishStatus.draft),
      exportSettings: jm(j['exportSettings']),
      extra: jm(j['extra']),
    );
  }

  String encode() => const JsonEncoder.withIndent(' ').convert(toJson());
  static ProjectDoc decode(String s) => ProjectDoc.fromJson(jsonDecode(s) as Map<String, dynamic>);

  bool descendsFrom(String rev) => rev == revision || ancestors.contains(rev);

  /// Prepares a new revision before saving (keeps lineage for conflicts).
  void bumpRevision(String device) {
    ancestors.add(revision);
    if (ancestors.length > 500) ancestors.removeRange(0, ancestors.length - 500);
    parentRevision = revision;
    revision = const Uuid().v4();
    modified = DateTime.now().toUtc();
    deviceId = device;
  }
}

class ProjectFormatException implements Exception {
  final String message;
  ProjectFormatException(this.message);
  @override
  String toString() => message;
}

/// Upgrades older project JSON to the current format version.
Map<String, dynamic> migrateProjectJson(Map<String, dynamic> j) {
  final out = Map<String, dynamic>.from(j);
  if (out['format'] != null && out['format'] != 'wojanmedia') {
    throw ProjectFormatException('To nie jest projekt WoJan Media Studio');
  }
  var v = ji(out['version'], 1);
  if (v > kProjectFormatVersion) {
    throw ProjectFormatException('Projekt utworzono w nowszej wersji aplikacji (format v$v). Zaktualizuj aplikację.');
  }
  // v1 → v2: assets were stored as a map {id: asset} and had 'path'
  if (v < 2) {
    final assets = out['assets'];
    if (assets is Map) {
      out['assets'] = assets.entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['id'] ??= e.key;
        m['relPath'] ??= m.remove('path') ?? '';
        return m;
      }).toList();
    }
    out['revision'] ??= const Uuid().v4();
    out['publish'] ??= {};
    v = 2;
  }
  out['version'] = v;
  return out;
}
