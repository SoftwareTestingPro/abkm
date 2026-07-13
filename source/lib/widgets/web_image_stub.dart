import 'package:flutter/material.dart';

Widget createWebImage(String url, {
  double? width, 
  double? height, 
  BoxFit? fit, 
  double topLeft = 0,
  double topRight = 0,
  double bottomLeft = 0,
  double bottomRight = 0,
}) {
  Widget img = Image.network(
    url,
    width: width,
    height: height,
    fit: fit ?? BoxFit.cover,
    errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 60),
  );
  if (topLeft >= 999) {
    return ClipOval(child: img);
  } else if (topLeft > 0 || topRight > 0 || bottomLeft > 0 || bottomRight > 0) {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(topLeft),
        topRight: Radius.circular(topRight),
        bottomLeft: Radius.circular(bottomLeft),
        bottomRight: Radius.circular(bottomRight),
      ),
      child: img,
    );
  }
  return img;
}
