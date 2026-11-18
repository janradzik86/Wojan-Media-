import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../project/format.dart';
import '../util/json_util.dart';

const publishStatusNames = <PublishStatus, String>{
  PublishStatus.draft: 'Szkic',
  PublishStatus.ready: 'Gotowy do przesłania',
  PublishStatus.pending: 'Oczekuje',
  PublishStatus.uploading: 'Przesyłanie',
  PublishStatus.handedOff: 'Przekazany do aplikacji docelowej',
  PublishStatus.uploaded: 'Przesłany do platformy',
  PublishStatus.scheduled: 'Zaplanowany',
  PublishStatus.published: 'Opublikowany',
  PublishStatus.error: 'Błąd',
  PublishStatus.needsApproval: 'Wymaga zatwierdzenia',
};

class PublishRecord {
  final String id;
  final String projectId;
  final String platform;
  final String fileSha256;
  final String filePath;
  String title, description;
  List<String> hashtags;
  String visibility;
  PublishStatus status;
  String? remoteId, url, error, account;
  DateTime created, updated;
  DateTime? scheduledAt;
  int bytesSent, bytesTotal;
  bool userApproved;

  PublishRecord({
    String? id,
    required this.projectId,
    required this.platform,
    required this.fileSha256,
    required this.filePath,
    this.title = '',
    this.description = '',
    List<String>? hashtags,
    this.visibility = 'private',
    this.status = PublishStatus.draft,
    this.remoteId,
    this.url,
    this.error,
    this.account,
    DateTime? created,
    DateTime? updated,
    this.scheduledAt,
    this.bytesSent = 0,
    this.bytesTotal = 0,
    this.userApproved = false,
  })  : id = id ?? const Uuid().v4(),
        hashtags = hashtags ?? [],
        created = created ?? DateTime.now().toUtc(),
        updated = updated ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'platform': platform,
        'sha256': fileSha256,
        'file': filePath,
        'title': title,
        'description': description,
        'hashtags': hashtags,
        'visibility': visibility,
        'status': status.name,
        'remoteId': remoteId,
        'url': url,
        'error': error,
        'account': account,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
        'scheduledAt': scheduledAt?.toIso8601String(),
        'bytesSent': bytesSent,
        'bytesTotal': bytesTotal,
        'approved': userApproved,
      };

  factory PublishRecord.fromJson(Map<String, dynamic> j) => PublishRecord(
        id: js(j['id']),
        projectId: js(j['projectId']),
        platform: js(j['platform']),
        fileSha256: js(j['sha256']),
        filePath: js(j['file']),
        title: js(j['title']),
        description: js(j['description']),
        hashtags: (j['hashtags'] as List?)?.map((e) => '$e').toList(),
        visibility: js(j['visibility'], 'private'),
        status: PublishStatus.values.firstWhere((e) => e.name == j['status'], orElse: () => PublishStatus.draft),
        remoteId: j['remoteId'] as String?,
        url: j['url'] as String?,
        error: j['error'] as String?,
        account: j['account'] as String?,
        created: DateTime.tryParse(js(j['created'])),
        updated: DateTime.tryParse(js(j['updated'])),
        scheduledAt: j['scheduledAt'] == null ? null : DateTime.tryParse('${j['scheduledAt']}'),
        bytesSent: ji(j['bytesSent']),
        bytesTotal: ji(j['bytesTotal']),
        userApproved: jb(j['approved']),
      );
}

/// Publication history + duplicate prevention (same file to same platform
/// and account is blocked unless the user explicitly overrides).
class PublishHistory {
  final File file;
  final List<PublishRecord> records = [];
  PublishHistory(this.file) {
    if (file.existsSync()) {
      try {
        records.addAll((jsonDecode(file.readAsStringSync()) as List).map((e) => PublishRecord.fromJson(Map<String, dynamic>.from(e as Map))));
      } catch (_) {}
    }
  }

  void save() {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(records.map((e) => e.toJson()).toList()));
    tmp.renameSync(file.path);
  }

  PublishRecord? duplicateOf(String sha, String platform, {String? account}) {
    for (final r in records) {
      if (r.fileSha256 == sha && r.platform == platform && (account == null || r.account == account) &&
          {PublishStatus.uploading, PublishStatus.uploaded, PublishStatus.scheduled, PublishStatus.published}.contains(r.status)) {
        return r;
      }
    }
    return null;
  }

  void upsert(PublishRecord r) {
    r.updated = DateTime.now().toUtc();
    final i = records.indexWhere((e) => e.id == r.id);
    if (i >= 0) {
      records[i] = r;
    } else {
      records.add(r);
    }
    save();
  }

  List<PublishRecord> forProject(String id) => records.where((r) => r.projectId == id).toList();
}
