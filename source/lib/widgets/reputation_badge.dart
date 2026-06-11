import 'dart:math';
import 'package:flutter/material.dart';

class SpikedStarPainter extends CustomPainter {
  final int spikes;
  final Color color;

  SpikedStarPainter({required this.spikes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Path path = Path();
    final double centerX = size.width / 2;
    final double centerY = size.height / 2;
    final double outerRadius = size.width / 2;
    final double innerRadius = outerRadius * 0.45;

    final double step = (pi * 2) / (spikes * 2);
    double angle = -pi / 2; // Start from top

    path.moveTo(
      centerX + outerRadius * cos(angle),
      centerY + outerRadius * sin(angle),
    );

    for (int i = 0; i < spikes * 2; i++) {
      angle += step;
      final double radius = (i % 2 == 0) ? innerRadius : outerRadius;
      path.lineTo(
        centerX + radius * cos(angle),
        centerY + radius * sin(angle),
      );
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SpikedStarPainter oldDelegate) {
    return oldDelegate.spikes != spikes || oldDelegate.color != color;
  }
}

class ReputationLevel {
  final int level;
  final int spikes;
  final String title;

  ReputationLevel({required this.level, required this.spikes, required this.title});
}

ReputationLevel getReputationLevel(int points) {
  if (points >= 100000) {
    return ReputationLevel(level: 10, spikes: 14, title: 'Level 10 Contributor');
  } else if (points >= 75000) {
    return ReputationLevel(level: 9, spikes: 12, title: 'Level 9 Contributor');
  } else if (points >= 50000) {
    return ReputationLevel(level: 8, spikes: 11, title: 'Level 8 Contributor');
  } else if (points >= 25000) {
    return ReputationLevel(level: 7, spikes: 10, title: 'Level 7 Contributor');
  } else if (points >= 10000) {
    return ReputationLevel(level: 6, spikes: 9, title: 'Level 6 Contributor');
  } else if (points >= 5000) {
    return ReputationLevel(level: 5, spikes: 8, title: 'Level 5 Contributor');
  } else if (points >= 1000) {
    return ReputationLevel(level: 4, spikes: 7, title: 'Level 4 Contributor');
  } else if (points >= 500) {
    return ReputationLevel(level: 3, spikes: 6, title: 'Level 3 Contributor');
  } else if (points >= 100) {
    return ReputationLevel(level: 2, spikes: 5, title: 'Level 2 Contributor');
  } else {
    return ReputationLevel(level: 1, spikes: 4, title: 'Level 1 Contributor');
  }
}

class ReputationBadge extends StatelessWidget {
  final int points;
  final double size;
  final bool showTooltip;

  const ReputationBadge({
    super.key,
    required this.points,
    this.size = 26,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    final rep = getReputationLevel(points);
    final badgeColor = const Color(0xFFE65100); // Google Maps contribution orange

    final badgeWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: badgeColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: max(1.0, size * 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: size * 0.15,
            offset: Offset(0, size * 0.08),
          )
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.56, size * 0.56),
          painter: SpikedStarPainter(spikes: rep.spikes, color: Colors.white),
        ),
      ),
    );

    if (showTooltip) {
      return Tooltip(
        message: 'Level ${rep.level} ($points referral points)',
        child: badgeWidget,
      );
    }
    return badgeWidget;
  }
}
