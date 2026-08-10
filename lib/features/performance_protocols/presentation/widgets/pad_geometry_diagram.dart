import 'package:flutter/material.dart';

/// A small diagram per pad geometry, so the five types read differently at a
/// glance.
///
/// Flutter port of `GeometryDiagram` in Hydrawave3
/// `apps/web/src/components/RecoveryResultPanel.jsx` — same 80×52 coordinate
/// space, same shapes, same `no pressure` caption on `bracket`, so a Sandwich
/// looks like a Sandwich in both clients.
///
/// The division of labour is the point: the 3D scene answers WHERE the pads sit,
/// this answers HOW the pair is meant to relate. The chip beside it gives the
/// name and the one-word reading ("Sandwich" / "through"); neither of those says
/// that the two pads face each other through the tissue, which is the thing a
/// practitioner has to get right.
class PadGeometryDiagram extends StatelessWidget {
  /// The authored `pad_geometry` key: `sandwich`, `wrap`, `side_by_side`,
  /// `diagonal` or `bracket`. Anything else draws the bare body outline, which is
  /// the web's fallback too — an unknown geometry must not invent a relationship.
  final String geometry;

  /// Pad fill. The pads here are deliberately NOT Sun/Moon coloured: the diagram
  /// is about the pairing, and colouring the two halves differently would imply
  /// which one is which when the authored geometry says nothing about that.
  final Color padColor;

  /// The body / joint outline and the connecting line.
  final Color bodyColor;
  final Color linkColor;

  /// Caption colour, used only by `bracket`.
  final Color captionColor;

  final double width;

  const PadGeometryDiagram({
    super.key,
    required this.geometry,
    required this.padColor,
    required this.bodyColor,
    required this.linkColor,
    required this.captionColor,
    this.width = 80,
  });

  @override
  Widget build(BuildContext context) {
    // 80×52 is the web viewBox; keeping the ratio keeps every shape's
    // proportions rather than re-tuning five sets of coordinates.
    return SizedBox(
      width: width,
      height: width * (52 / 80),
      child: CustomPaint(
        painter: _PadGeometryPainter(
          geometry: geometry.trim().toLowerCase(),
          padColor: padColor,
          bodyColor: bodyColor,
          linkColor: linkColor,
          captionColor: captionColor,
        ),
      ),
    );
  }
}

class _PadGeometryPainter extends CustomPainter {
  final String geometry;
  final Color padColor;
  final Color bodyColor;
  final Color linkColor;
  final Color captionColor;

  _PadGeometryPainter({
    required this.geometry,
    required this.padColor,
    required this.bodyColor,
    required this.linkColor,
    required this.captionColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scale the web's 80×52 space onto whatever box we were given.
    final s = size.width / 80.0;
    Offset pt(double x, double y) => Offset(x * s, y * s);
    Rect box(double x, double y, double w, double h) =>
        Rect.fromLTWH(x * s, y * s, w * s, h * s);

    final padPaint = Paint()..color = padColor;
    final bodyFill = Paint()..color = bodyColor.withValues(alpha: 0.18);
    final bodyStroke = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * s;
    final linkPaint = Paint()
      ..color = linkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * s
      ..strokeCap = StrokeCap.round;

    // One pad: 14×10 with a 2-unit radius, as in the web.
    void pad(double x, double y) => canvas.drawRRect(
          RRect.fromRectAndRadius(box(x, y, 14, 10), Radius.circular(2 * s)),
          padPaint,
        );

    // The torso block every geometry except `wrap`/`diagonal`/`bracket` sits on.
    void body() {
      final r = RRect.fromRectAndRadius(box(26, 6, 28, 38), Radius.circular(6 * s));
      canvas.drawRRect(r, bodyFill);
      canvas.drawRRect(r, bodyStroke);
    }

    void circleAt(double cx, double cy, double radius, {bool fill = true}) {
      if (fill) canvas.drawCircle(pt(cx, cy), radius * s, bodyFill);
      canvas.drawCircle(pt(cx, cy), radius * s, bodyStroke);
    }

    void quad(double x1, double y1, double cx, double cy, double x2, double y2,
        Paint paint) {
      final path = Path()
        ..moveTo(x1 * s, y1 * s)
        ..quadraticBezierTo(cx * s, cy * s, x2 * s, y2 * s);
      canvas.drawPath(path, paint);
    }

    switch (geometry) {
      case 'sandwich':
        // Two pads facing each other THROUGH the tissue.
        body();
        pad(6, 20);
        pad(60, 20);
        canvas.drawLine(pt(20, 25), pt(60, 25), linkPaint);
        break;

      case 'wrap':
        // Opposite sides of a joint, bracketing it — the link arcs over the top.
        circleAt(40, 25, 15);
        pad(8, 20);
        pad(58, 20);
        quad(22, 25, 40, 6, 58, 25, linkPaint);
        break;

      case 'side_by_side':
        // Both pads on ONE surface, stacked along the muscle.
        body();
        pad(31, 12);
        pad(31, 30);
        canvas.drawLine(pt(38, 22), pt(38, 30), linkPaint);
        break;

      case 'diagonal':
        // Offset pairing so contact holds on a curved surface — the body itself
        // is drawn as the curve, unfilled.
        quad(18, 44, 40, 4, 62, 44, bodyStroke);
        pad(16, 30);
        pad(52, 14);
        canvas.drawLine(pt(30, 33), pt(54, 21), linkPaint);
        break;

      case 'bracket':
        // AROUND the node, deliberately with NO link drawn between the pads: the
        // absence is the instruction, and the caption says so in words.
        circleAt(40, 25, 10);
        pad(8, 20);
        pad(58, 20);
        _caption(canvas, size, s, 'no pressure');
        break;

      default:
        // Unknown geometry — outline only, no implied relationship.
        body();
    }
  }

  void _caption(Canvas canvas, Size size, double s, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: captionColor,
          fontSize: 8 * s,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset((size.width - painter.width) / 2, 42 * s),
    );
  }

  @override
  bool shouldRepaint(_PadGeometryPainter old) =>
      old.geometry != geometry ||
      old.padColor != padColor ||
      old.bodyColor != bodyColor ||
      old.linkColor != linkColor ||
      old.captionColor != captionColor;
}
