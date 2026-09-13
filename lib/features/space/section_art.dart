import 'package:flutter/material.dart';
import '../../main.dart';

/// Resolution-independent illustrations, with matching accessibility labels.
class SectionArt extends StatelessWidget {
  final bool fitness;
  const SectionArt({super.key, required this.fitness});
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: fitness ? 'Heart and activity' : 'Calendar and clock',
    child: SizedBox(
      width: 115,
      height: 78,
      child: CustomPaint(painter: _SectionPainter(fitness)),
    ),
  );
}

class _SectionPainter extends CustomPainter {
  final bool fitness;
  _SectionPainter(this.fitness);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 115, size.height / 78);
    final fill = Paint()..color = soft;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawOval(const Rect.fromLTWH(2, 4, 110, 71), fill);
    if (fitness) {
      final heart = Path()
        ..moveTo(49, 60)
        ..cubicTo(39, 52, 16, 36, 22, 22)
        ..cubicTo(28, 8, 45, 13, 49, 23)
        ..cubicTo(56, 9, 75, 12, 77, 26)
        ..cubicTo(80, 39, 61, 53, 49, 60);
      canvas.drawPath(heart, Paint()..color = const Color(0xFFDCE7D6));
      canvas.drawPath(heart, stroke);
      canvas.drawPath(
        Path()
          ..moveTo(27, 37)
          ..lineTo(39, 37)
          ..lineTo(44, 28)
          ..lineTo(50, 45)
          ..lineTo(56, 35)
          ..lineTo(68, 35),
        stroke,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(72, 48, 29, 21),
          const Radius.circular(6),
        ),
        Paint()..color = Colors.white,
      );
      canvas.drawLine(const Offset(77, 58), const Offset(96, 58), stroke);
      canvas.drawLine(const Offset(79, 53), const Offset(79, 63), stroke);
      canvas.drawLine(const Offset(94, 53), const Offset(94, 63), stroke);
    } else {
      final rect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(14, 14, 65, 52),
        const Radius.circular(9),
      );
      canvas.drawRRect(rect, Paint()..color = Colors.white);
      canvas.drawRRect(rect, stroke);
      canvas.drawLine(const Offset(14, 29), const Offset(79, 29), stroke);
      canvas.drawLine(const Offset(30, 9), const Offset(30, 19), stroke);
      canvas.drawLine(const Offset(63, 9), const Offset(63, 19), stroke);
      canvas.drawPath(
        Path()
          ..moveTo(25, 43)
          ..lineTo(30, 48)
          ..lineTo(40, 38),
        stroke,
      );
      canvas.drawLine(const Offset(48, 42), const Offset(61, 42), stroke);
      canvas.drawCircle(
        const Offset(85, 54),
        18,
        Paint()..color = const Color(0xFFDCE7D6),
      );
      canvas.drawCircle(const Offset(85, 54), 18, stroke);
      canvas.drawPath(
        Path()
          ..moveTo(85, 43)
          ..lineTo(85, 54)
          ..lineTo(93, 59),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SectionPainter oldDelegate) =>
      fitness != oldDelegate.fitness;
}

class PetSectionArt extends StatelessWidget {
  const PetSectionArt({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Two paw prints for Cookie and Wanwan',
    child: SizedBox(
      width: 115,
      height: 78,
      child: Stack(
        children: [
          Positioned(
            left: 2,
            top: 4,
            child: Container(
              width: 110,
              height: 71,
              decoration: const BoxDecoration(
                color: soft,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Positioned(
            left: 12,
            top: 6,
            child: Icon(Icons.pets_rounded, size: 54, color: ink),
          ),
          const Positioned(
            right: 6,
            bottom: 4,
            child: Icon(Icons.pets_rounded, size: 40, color: Color(0xFF9A6845)),
          ),
        ],
      ),
    ),
  );
}
