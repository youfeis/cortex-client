import 'package:flutter/material.dart';
import '../core/cortex.dart';
import '../main.dart';

class CortexAvatar extends StatelessWidget {
  const CortexAvatar({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Cortex, a little owl',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _Owl()),
    ),
  );
}

class _Owl extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    final p = Paint()..isAntiAlias = true;
    canvas.drawCircle(const Offset(32, 32), 32, p..color = soft);
    final body = Path()
      ..moveTo(14, 20)
      ..quadraticBezierTo(10, 5, 25, 17)
      ..quadraticBezierTo(32, 14, 39, 17)
      ..quadraticBezierTo(54, 5, 50, 20)
      ..cubicTo(57, 44, 49, 55, 32, 55)
      ..cubicTo(15, 55, 7, 44, 14, 20)
      ..close();
    canvas.drawPath(body, p..color = ink);
    canvas.drawOval(
      const Rect.fromLTWH(15, 23, 21, 25),
      p..color = const Color(0xFFF6F3DF),
    );
    canvas.drawOval(const Rect.fromLTWH(28, 23, 21, 25), p);
    for (final x in [24.0, 40.0]) {
      canvas.drawCircle(Offset(x, 32), 4.4, p..color = ink);
      canvas.drawCircle(Offset(x + 1, 30.5), 1.25, p..color = Colors.white);
    }
    canvas.drawPath(
      Path()
        ..moveTo(28, 39)
        ..lineTo(36, 39)
        ..lineTo(32, 44)
        ..close(),
      p..color = const Color(0xFFD3A85A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(21, 53, 9, 3),
        const Radius.circular(2),
      ),
      p,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(34, 53, 9, 3),
        const Radius.circular(2),
      ),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _Owl oldDelegate) => false;
}

class OwnerAvatar extends StatelessWidget {
  const OwnerAvatar({super.key, required this.model, this.size = 32});
  final CortexModel model;
  final double size;
  @override
  Widget build(BuildContext context) {
    final id = model.ownerAvatarId;
    final fallback = ColoredBox(
      color: soft,
      child: Icon(Icons.person_outline, size: size * .65, color: ink),
    );
    return Semantics(
      label: 'Your avatar',
      image: true,
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: id == null
              ? fallback
              : FutureBuilder(
                  future: model.image(id),
                  builder: (context, snapshot) => snapshot.hasData
                      ? Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : fallback,
                ),
        ),
      ),
    );
  }
}

Widget messageContent(
  CortexModel model,
  bool owner, {
  required Widget child,
}) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (!owner) ...[const CortexAvatar(size: 40), const SizedBox(width: 12)],
    Expanded(child: child),
    if (owner) ...[
      const SizedBox(width: 12),
      OwnerAvatar(model: model, size: 40),
    ],
  ],
);
