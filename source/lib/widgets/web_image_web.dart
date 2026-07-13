import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
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
  final String viewType = 'gimg-${url.hashCode}-${topLeft.toInt()}-${topRight.toInt()}-${bottomLeft.toInt()}-${bottomRight.toInt()}';
  
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final img = html.ImageElement()
      ..src = url
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = fit == BoxFit.cover ? 'cover' : 'contain';
      
    if (topLeft >= 999) {
      img.style.borderRadius = '50%';
    } else if (topLeft > 0 || topRight > 0 || bottomLeft > 0 || bottomRight > 0) {
      img.style.borderRadius = '${topLeft}px ${topRight}px ${bottomRight}px ${bottomLeft}px';
    }
    return img;
  });

  return SizedBox(
    width: width,
    height: height,
    child: HtmlElementView(viewType: viewType),
  );
}
