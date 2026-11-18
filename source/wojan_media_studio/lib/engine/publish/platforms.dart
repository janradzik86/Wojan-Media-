import 'dart:convert';

import '../export/video_export.dart';
import '../ffmpeg/probe.dart';
import '../util/json_util.dart';

/// Publication profile of a platform. Limits are DATA (updatable JSON),
/// never hard-coded assumptions – see [PlatformProfiles.updateFromJson].
class PlatformProfile {
  final String id, name;
  final int aspectW, aspectH;
  final int width, height;
  final double fps;
  final int maxDurationSec; // 0 = unknown/unlimited
  final int minDurationSec;
  final int maxSizeMB; // 0 = unknown
  final int maxTitle, maxDescription, maxHashtags;
  final List<String> codecs;
  final int videoKbps;
  final String uploadUrl; // official web upload page
  final String? androidPackage; // native app for direct share
  final bool apiPublishing; // official API implemented in app
  final String notes;
  const PlatformProfile({
    required this.id,
    required this.name,
    required this.aspectW,
    required this.aspectH,
    required this.width,
    required this.height,
    this.fps = 30,
    this.maxDurationSec = 0,
    this.minDurationSec = 0,
    this.maxSizeMB = 0,
    this.maxTitle = 0,
    this.maxDescription = 0,
    this.maxHashtags = 0,
    this.codecs = const ['h264'],
    this.videoKbps = 8000,
    this.uploadUrl = '',
    this.androidPackage,
    this.apiPublishing = false,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'aspect': [aspectW, aspectH],
        'size': [width, height],
        'fps': fps,
        'maxDurationSec': maxDurationSec,
        'minDurationSec': minDurationSec,
        'maxSizeMB': maxSizeMB,
        'maxTitle': maxTitle,
        'maxDescription': maxDescription,
        'maxHashtags': maxHashtags,
        'codecs': codecs,
        'videoKbps': videoKbps,
        'uploadUrl': uploadUrl,
        'androidPackage': androidPackage,
        'apiPublishing': apiPublishing,
        'notes': notes,
      };

  factory PlatformProfile.fromJson(Map<String, dynamic> j) {
    final a = (j['aspect'] as List?) ?? [16, 9];
    final s = (j['size'] as List?) ?? [1920, 1080];
    return PlatformProfile(
      id: js(j['id']),
      name: js(j['name']),
      aspectW: ji(a[0]),
      aspectH: ji(a[1]),
      width: ji(s[0]),
      height: ji(s[1]),
      fps: jd(j['fps'], 30),
      maxDurationSec: ji(j['maxDurationSec']),
      minDurationSec: ji(j['minDurationSec']),
      maxSizeMB: ji(j['maxSizeMB']),
      maxTitle: ji(j['maxTitle']),
      maxDescription: ji(j['maxDescription']),
      maxHashtags: ji(j['maxHashtags']),
      codecs: (j['codecs'] as List?)?.map((e) => '$e').toList() ?? ['h264'],
      videoKbps: ji(j['videoKbps'], 8000),
      uploadUrl: js(j['uploadUrl']),
      androidPackage: j['androidPackage'] as String?,
      apiPublishing: jb(j['apiPublishing']),
      notes: js(j['notes']),
    );
  }

  VideoExportSettings exportSettings() => VideoExportSettings(width: width, height: height, fps: fps, bitrateKbps: videoKbps, codec: VideoCodec.h264, preset: 'medium');
}

/// Default profiles (values as documented by the platforms at the time of
/// writing – 2026-11; editable and updatable from a signed JSON feed).
const _defaults = <PlatformProfile>[
  PlatformProfile(id: 'tiktok', name: 'TikTok', aspectW: 9, aspectH: 16, width: 1080, height: 1920, maxDurationSec: 600, minDurationSec: 3, maxSizeMB: 500, maxDescription: 4000, videoKbps: 8000, uploadUrl: 'https://www.tiktok.com/upload', androidPackage: 'com.zhiliaoapp.musically', notes: 'Content Posting API wymaga audytu aplikacji przez TikTok – udostępnianie systemowe/strona przesyłania.'),
  PlatformProfile(id: 'youtube_shorts', name: 'YouTube Shorts', aspectW: 9, aspectH: 16, width: 1080, height: 1920, maxDurationSec: 180, maxSizeMB: 0, maxTitle: 100, maxDescription: 5000, maxHashtags: 15, videoKbps: 10000, uploadUrl: 'https://studio.youtube.com', androidPackage: 'com.google.android.youtube', apiPublishing: true),
  PlatformProfile(id: 'instagram_reels', name: 'Instagram Reels', aspectW: 9, aspectH: 16, width: 1080, height: 1920, maxDurationSec: 900, minDurationSec: 3, maxSizeMB: 1000, maxDescription: 2200, maxHashtags: 30, videoKbps: 8000, uploadUrl: 'https://www.instagram.com', androidPackage: 'com.instagram.android', notes: 'Graph API publikacji wymaga konta firmowego i weryfikacji aplikacji Meta.'),
  PlatformProfile(id: 'facebook_reels', name: 'Facebook Reels', aspectW: 9, aspectH: 16, width: 1080, height: 1920, maxDurationSec: 90, minDurationSec: 3, maxSizeMB: 1000, maxDescription: 63206, videoKbps: 8000, uploadUrl: 'https://www.facebook.com/reels/create', androidPackage: 'com.facebook.katana'),
  PlatformProfile(id: 'youtube', name: 'YouTube', aspectW: 16, aspectH: 9, width: 1920, height: 1080, maxDurationSec: 43200, maxSizeMB: 262144, maxTitle: 100, maxDescription: 5000, maxHashtags: 15, videoKbps: 12000, uploadUrl: 'https://studio.youtube.com', androidPackage: 'com.google.android.youtube', apiPublishing: true, notes: 'Filmy dłuższe niż 15 min wymagają zweryfikowanego konta.'),
  PlatformProfile(id: 'facebook', name: 'Facebook', aspectW: 16, aspectH: 9, width: 1920, height: 1080, maxDurationSec: 14400, maxSizeMB: 10240, maxDescription: 63206, videoKbps: 10000, uploadUrl: 'https://www.facebook.com', androidPackage: 'com.facebook.katana'),
  PlatformProfile(id: 'instagram_square', name: 'Instagram 1:1', aspectW: 1, aspectH: 1, width: 1080, height: 1080, maxDurationSec: 900, maxDescription: 2200, maxHashtags: 30, videoKbps: 6000, uploadUrl: 'https://www.instagram.com', androidPackage: 'com.instagram.android'),
  PlatformProfile(id: 'feed_4x5', name: 'Format 4:5 (feed)', aspectW: 4, aspectH: 5, width: 1080, height: 1350, maxDurationSec: 900, maxDescription: 2200, videoKbps: 6000, uploadUrl: 'https://www.instagram.com', androidPackage: 'com.instagram.android'),
  PlatformProfile(id: 'x', name: 'X', aspectW: 16, aspectH: 9, width: 1280, height: 720, maxDurationSec: 140, maxSizeMB: 512, maxDescription: 280, videoKbps: 5000, uploadUrl: 'https://x.com/compose/post', androidPackage: 'com.twitter.android', notes: 'Publikacja przez API X jest płatna – używane jest udostępnianie systemowe.'),
  PlatformProfile(id: 'threads', name: 'Threads', aspectW: 9, aspectH: 16, width: 1080, height: 1920, maxDurationSec: 300, maxDescription: 500, videoKbps: 6000, uploadUrl: 'https://www.threads.net', androidPackage: 'com.instagram.barcelona'),
  PlatformProfile(id: 'whatsapp', name: 'WhatsApp', aspectW: 9, aspectH: 16, width: 720, height: 1280, maxSizeMB: 100, videoKbps: 2500, androidPackage: 'com.whatsapp'),
  PlatformProfile(id: 'telegram', name: 'Telegram', aspectW: 16, aspectH: 9, width: 1920, height: 1080, maxSizeMB: 2048, videoKbps: 6000, androidPackage: 'org.telegram.messenger'),
  PlatformProfile(id: 'messenger', name: 'Messenger', aspectW: 9, aspectH: 16, width: 720, height: 1280, maxSizeMB: 25, videoKbps: 1500, androidPackage: 'com.facebook.orca'),
  PlatformProfile(id: 'discord', name: 'Discord', aspectW: 16, aspectH: 9, width: 1280, height: 720, maxSizeMB: 10, videoKbps: 900, androidPackage: 'com.discord', notes: 'Limit pliku zależy od planu Nitro/serwera.'),
];

class PlatformProfiles {
  final Map<String, PlatformProfile> _p = {for (final p in _defaults) p.id: p};
  int version = 1;
  List<PlatformProfile> get all => _p.values.toList();
  PlatformProfile? operator [](String id) => _p[id];

  /// Applies an updated profile feed `{version, profiles:[...]}`.
  bool updateFromJson(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final v = ji(j['version']);
    if (v <= version) return false;
    for (final p in jl(j['profiles'])) {
      final prof = PlatformProfile.fromJson(p);
      if (prof.id.isNotEmpty) _p[prof.id] = prof;
    }
    version = v;
    return true;
  }

  String toJson() => jsonEncode({'version': version, 'profiles': all.map((e) => e.toJson()).toList()});
}

enum IssueLevel { ok, warning, error }

class PublishIssue {
  final IssueLevel level;
  final String message;
  PublishIssue(this.level, this.message);
  @override
  String toString() => '${level.name}: $message';
}

/// Smart pre-publication check of a rendered file against a profile.
List<PublishIssue> checkForPlatform(PlatformProfile p, MediaInfo info, {String title = '', String description = '', List<String> hashtags = const [], bool hasThumbnail = false}) {
  final out = <PublishIssue>[];
  final w = info.displayWidth ?? 0, h = info.displayHeight ?? 0;
  if (w > 0 && h > 0) {
    final ar = w / h, want = p.aspectW / p.aspectH;
    if ((ar - want).abs() > 0.02) {
      out.add(PublishIssue(IssueLevel.warning, 'Proporcje ${w}x$h nie odpowiadają ${p.aspectW}:${p.aspectH} – wyrenderuj wersję dla ${p.name}.'));
    }
    if (h < p.height * 0.66 && w < p.width * 0.66) out.add(PublishIssue(IssueLevel.warning, 'Niska rozdzielczość (${w}x$h); zalecane ${p.width}x${p.height}.'));
  }
  if (info.videoCodec != null && !p.codecs.contains(info.videoCodec == 'hevc' ? 'h265' : info.videoCodec)) {
    out.add(PublishIssue(IssueLevel.warning, 'Kodek ${info.videoCodec} może nie być obsługiwany – zalecany ${p.codecs.join('/')}.'));
  }
  if (p.maxDurationSec > 0 && info.duration > p.maxDurationSec) {
    out.add(PublishIssue(IssueLevel.error, 'Film trwa ${info.duration.toStringAsFixed(0)} s, limit ${p.name}: ${p.maxDurationSec} s.'));
  }
  if (p.minDurationSec > 0 && info.duration < p.minDurationSec) out.add(PublishIssue(IssueLevel.error, 'Film jest za krótki (min. ${p.minDurationSec} s).'));
  if (p.maxSizeMB > 0 && info.sizeBytes > p.maxSizeMB * 1024 * 1024) {
    out.add(PublishIssue(IssueLevel.error, 'Plik ma ${(info.sizeBytes / 1048576).toStringAsFixed(0)} MB, limit: ${p.maxSizeMB} MB – użyj kompresji.'));
  }
  if (info.bitrate != null && info.bitrate! > p.videoKbps * 1000 * 2.5) {
    out.add(PublishIssue(IssueLevel.warning, 'Bitrate ${(info.bitrate! / 1000).round()} kb/s jest wysoki – platforma i tak przekoduje plik.'));
  }
  if (p.maxTitle > 0 && title.length > p.maxTitle) out.add(PublishIssue(IssueLevel.error, 'Tytuł ma ${title.length} znaków (limit ${p.maxTitle}).'));
  final descLen = description.length + hashtags.fold<int>(0, (s, h) => s + h.length + 2);
  if (p.maxDescription > 0 && descLen > p.maxDescription) out.add(PublishIssue(IssueLevel.error, 'Opis z hashtagami ma $descLen znaków (limit ${p.maxDescription}).'));
  if (p.maxHashtags > 0 && hashtags.length > p.maxHashtags) out.add(PublishIssue(IssueLevel.warning, 'Za dużo hashtagów (${hashtags.length}, zalecane ≤ ${p.maxHashtags}).'));
  if (!info.hasAudio) out.add(PublishIssue(IssueLevel.warning, 'Film nie zawiera dźwięku.'));
  if (p.id.startsWith('youtube') && !hasThumbnail && p.id == 'youtube') out.add(PublishIssue(IssueLevel.warning, 'Brak miniatury – YouTube wygeneruje ją automatycznie.'));
  if (out.isEmpty) out.add(PublishIssue(IssueLevel.ok, 'Plik spełnia wymagania ${p.name}.'));
  return out;
}

/// Normalises hashtags: `#tag` form, no spaces/duplicates.
List<String> normalizeHashtags(String raw) {
  final out = <String>[];
  for (var t in raw.split(RegExp(r'[\s,;]+'))) {
    t = t.trim();
    if (t.isEmpty) continue;
    t = t.replaceAll('#', '');
    t = t.replaceAll(RegExp(r'[^\p{L}\p{N}_]', unicode: true), '');
    if (t.isEmpty) continue;
    final tag = '#$t';
    if (!out.any((e) => e.toLowerCase() == tag.toLowerCase())) out.add(tag);
  }
  return out;
}
