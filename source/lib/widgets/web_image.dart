import 'package:flutter/material.dart';
import 'web_image_stub.dart'
    if (dart.library.html) 'web_image_web.dart' as impl;

class GoogleProfileImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final double topLeft;
  final double topRight;
  final double bottomLeft;
  final double bottomRight;

  const GoogleProfileImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
    this.topLeft = 0,
    this.topRight = 0,
    this.bottomLeft = 0,
    this.bottomRight = 0,
  });

  @override
  Widget build(BuildContext context) {
    return impl.createWebImage(
      url,
      width: width,
      height: height,
      fit: fit,
      topLeft: topLeft,
      topRight: topRight,
      bottomLeft: bottomLeft,
      bottomRight: bottomRight,
    );
  }
}
