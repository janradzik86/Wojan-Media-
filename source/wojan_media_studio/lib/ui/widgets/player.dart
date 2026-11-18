import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Real playback of rendered previews / media files (libmpv via media_kit,
/// hardware decoding where available).
class PreviewPlayer extends StatefulWidget {
  final String? path;
  final bool audioOnly;
  final double aspect;
  final void Function(Player p)? onCreated;
  const PreviewPlayer({super.key, this.path, this.audioOnly = false, this.aspect = 16 / 9, this.onCreated});
  @override
  State<PreviewPlayer> createState() => PreviewPlayerState();
}

class PreviewPlayerState extends State<PreviewPlayer> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  String? _loaded;

  @override
  void initState() {
    super.initState();
    widget.onCreated?.call(player);
    _load();
  }

  @override
  void didUpdateWidget(covariant PreviewPlayer old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    if (widget.path != null && widget.path != _loaded) {
      _loaded = widget.path;
      player.open(Media(widget.path!), play: false);
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.path == null) {
      return AspectRatio(aspectRatio: widget.aspect, child: Container(color: Colors.black, alignment: Alignment.center, child: const Text('Brak podglądu – wygeneruj podgląd', style: TextStyle(color: Colors.white54))));
    }
    if (widget.audioOnly) {
      return Card(child: Padding(padding: const EdgeInsets.all(8), child: _Controls(player: player)));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: AspectRatio(aspectRatio: widget.aspect, child: Video(controller: controller, controls: NoVideoControls, fill: Colors.black))),
      _Controls(player: player),
    ]);
  }
}

class _Controls extends StatelessWidget {
  final Player player;
  const _Controls({required this.player});
  String _f(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
        stream: player.stream.position,
        builder: (c, s) {
          final pos = s.data ?? Duration.zero;
          final dur = player.state.duration;
          return Row(children: [
            StreamBuilder<bool>(stream: player.stream.playing, builder: (c, p) => IconButton(icon: Icon((p.data ?? false) ? Icons.pause : Icons.play_arrow), onPressed: player.playOrPause)),
            Text(_f(pos)),
            Expanded(
              child: Slider(
                value: dur.inMilliseconds == 0 ? 0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0),
                onChanged: (v) => player.seek(Duration(milliseconds: (v * dur.inMilliseconds).round())),
              ),
            ),
            Text(_f(dur)),
          ]);
        },
      );
}
