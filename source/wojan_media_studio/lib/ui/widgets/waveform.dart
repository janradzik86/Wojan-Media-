import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

/// Waveform with zoom, scroll, range selection, playhead, markers & beats.
class WaveformView extends StatefulWidget {
  final Float32List peaks; // min/max pairs over the full duration
  final double duration;
  final double selStart, selEnd; // seconds (selEnd<=selStart → none)
  final double playhead;
  final List<double> markers;
  final List<double> beats;
  final double zoom; // 1 = fit
  final double scroll; // 0..1 start position fraction
  final Color color;
  final void Function(double s, double e) onSelect;
  final void Function(double t)? onSeek;
  final double height;
  const WaveformView({super.key, required this.peaks, required this.duration, this.selStart = 0, this.selEnd = 0, this.playhead = -1, this.markers = const [], this.beats = const [], this.zoom = 1, this.scroll = 0, this.color = WmsColors.accent, required this.onSelect, this.onSeek, this.height = 140});
  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  double? _dragStart;
  double _t(double dx, double w) {
    final visible = widget.duration / widget.zoom;
    final start = widget.scroll * (widget.duration - visible);
    return (start + dx / w * visible).clamp(0, widget.duration).toDouble();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, cons) {
        final w = cons.maxWidth;
        return GestureDetector(
          onTapUp: (d) => widget.onSeek?.call(_t(d.localPosition.dx, w)),
          onHorizontalDragStart: (d) => _dragStart = _t(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) {
            final t = _t(d.localPosition.dx, w);
            final s = _dragStart ?? t;
            widget.onSelect(s < t ? s : t, s < t ? t : s);
          },
          child: SizedBox(
            height: widget.height,
            width: w,
            child: CustomPaint(painter: _WavePainter(widget)),
          ),
        );
      });
}

class _WavePainter extends CustomPainter {
  final WaveformView v;
  _WavePainter(this.v);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0C0E11));
    if (v.peaks.isEmpty || v.duration <= 0) return;
    final n = v.peaks.length ~/ 2;
    final visible = v.duration / v.zoom;
    final start = v.scroll * (v.duration - visible);
    double x(double t) => (t - start) / visible * size.width;
    final mid = size.height / 2;
    // beats
    final bp = Paint()..color = Colors.white.withValues(alpha: 0.08);
    for (final b in v.beats) {
      final bx = x(b);
      if (bx >= 0 && bx <= size.width) canvas.drawLine(Offset(bx, 0), Offset(bx, size.height), bp);
    }
    // selection
    if (v.selEnd > v.selStart) {
      canvas.drawRect(Rect.fromLTRB(x(v.selStart), 0, x(v.selEnd), size.height), Paint()..color = WmsColors.accent2.withValues(alpha: 0.22));
    }
    final p = Paint()
      ..color = v.color
      ..strokeWidth = 1;
    for (var px = 0; px < size.width; px++) {
      final t0 = start + px / size.width * visible, t1 = start + (px + 1) / size.width * visible;
      final i0 = (t0 / v.duration * n).floor().clamp(0, n - 1), i1 = (t1 / v.duration * n).ceil().clamp(i0 + 1, n);
      var mn = 0.0, mx = 0.0;
      for (var i = i0; i < i1; i++) {
        if (v.peaks[i * 2] < mn) mn = v.peaks[i * 2];
        if (v.peaks[i * 2 + 1] > mx) mx = v.peaks[i * 2 + 1];
      }
      canvas.drawLine(Offset(px.toDouble(), mid - mx * mid * 0.95), Offset(px.toDouble(), mid - mn * mid * 0.95), p);
    }
    final mp = Paint()..color = WmsColors.warn;
    for (final m in v.markers) {
      final mx = x(m);
      canvas.drawLine(Offset(mx, 0), Offset(mx, size.height), mp);
    }
    if (v.playhead >= 0) {
      final px = x(v.playhead);
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), Paint()
        ..color = Colors.white
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}
