import 'dart:io';
import 'dart:math';
import 'package:image/image.dart';

void main() {
  final templateFile = File('assets/images/app_icon.png');
  if (!templateFile.existsSync()) {
    print('Error: app_icon.png template not found in assets/images/');
    return;
  }

  final bytes = templateFile.readAsBytesSync();
  var image = decodeImage(bytes);
  if (image == null) {
    print('Error: Could not decode app_icon.png');
    return;
  }

  print('Loaded app_icon.png: ${image.width}x${image.height}');
  if (image.numChannels < 4 || !image.hasAlpha) {
    print('Converting app_icon.png to RGBA to support transparency channel...');
    image = image.convert(numChannels: 4);
  }

  // 1. Mask the image with a circle (make everything outside transparent)
  final double cx = (image.width - 1) / 2.0;
  final double cy = (image.height - 1) / 2.0;
  final double maxRadius = min(image.width, image.height) / 2.0;
  // Leave a clean border margin
  final double maskRadius = maxRadius - 1.5; 

  print('Center: ($cx, $cy), Max Radius: $maxRadius, Mask Radius: $maskRadius');

  for (final pixel in image) {
    final x = pixel.x;
    final y = pixel.y;
    final dx = x - cx;
    final dy = y - cy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist > maskRadius) {
      pixel.r = 0;
      pixel.g = 0;
      pixel.b = 0;
      pixel.a = 0;
    }
  }

  // Save the circular masked icon back to the assets
  final maskedPng = encodePng(image);
  File('assets/images/app_icon.png').writeAsBytesSync(maskedPng);
  print('Saved circular masked app_icon.png');

  // 2. Generate standard logos in assets/images/
  final logoSmall = copyResize(image, width: 128, height: 128, interpolation: Interpolation.average);
  File('assets/images/logo_small.png').writeAsBytesSync(encodePng(logoSmall));
  print('Generated logo_small.png (128x128)');

  final logoMedium = copyResize(image, width: 256, height: 256, interpolation: Interpolation.average);
  File('assets/images/logo_medium.png').writeAsBytesSync(encodePng(logoMedium));
  print('Generated logo_medium.png (256x256)');

  final logoLarge = copyResize(image, width: 512, height: 512, interpolation: Interpolation.average);
  File('assets/images/logo_large.png').writeAsBytesSync(encodePng(logoLarge));
  print('Generated logo_large.png (512x512)');

  // 3. Generate Android launch icon
  final launchImage = copyResize(image, width: 256, height: 256, interpolation: Interpolation.average);
  final androidResFile = File('android/app/src/main/res/drawable/launch_image_small.png');
  androidResFile.createSync(recursive: true);
  androidResFile.writeAsBytesSync(encodePng(launchImage));
  print('Generated Android launch_image_small.png (256x256)');

  // 4. Generate Standard Web icons
  final webIcon512 = copyResize(image, width: 512, height: 512, interpolation: Interpolation.average);
  final webIconsDir = Directory('web/icons');
  webIconsDir.createSync(recursive: true);
  File('web/icons/Icon-512.png').writeAsBytesSync(encodePng(webIcon512));
  print('Generated web/icons/Icon-512.png (512x512)');

  final webIcon192 = copyResize(image, width: 192, height: 192, interpolation: Interpolation.average);
  File('web/icons/Icon-192.png').writeAsBytesSync(encodePng(webIcon192));
  print('Generated web/icons/Icon-192.png (192x192)');

  // 5. Generate Maskable PWA icons (with solid white background and shrunk logo to fit safe zone)
  // Maskable 512x512
  final maskableCanvas512 = Image(width: 512, height: 512);
  fill(maskableCanvas512, color: ColorRgba8(255, 255, 255, 255));
  final shrunkLogo512 = copyResize(image, width: 410, height: 410, interpolation: Interpolation.average);
  compositeImage(maskableCanvas512, shrunkLogo512, dstX: 51, dstY: 51);
  File('web/icons/Icon-maskable-512.png').writeAsBytesSync(encodePng(maskableCanvas512));
  print('Generated web/icons/Icon-maskable-512.png (512x512)');

  // Maskable 192x192
  final maskableCanvas192 = Image(width: 192, height: 192);
  fill(maskableCanvas192, color: ColorRgba8(255, 255, 255, 255));
  final shrunkLogo192 = copyResize(image, width: 154, height: 154, interpolation: Interpolation.average);
  compositeImage(maskableCanvas192, shrunkLogo192, dstX: 19, dstY: 19);
  File('web/icons/Icon-maskable-192.png').writeAsBytesSync(encodePng(maskableCanvas192));
  print('Generated web/icons/Icon-maskable-192.png (192x192)');

  // 6. Copy all generated assets to the outer deploy directories for safety
  try {
    print('Copying all clean assets to outer deploy directories for live serving...');
    final outerAssetsDir = Directory('../assets/assets/images');
    outerAssetsDir.createSync(recursive: true);
    final outerIconsDir = Directory('../icons');
    outerIconsDir.createSync(recursive: true);

    File('assets/images/app_icon.png').copySync('../assets/assets/images/app_icon.png');
    File('assets/images/logo_large.png').copySync('../assets/assets/images/logo_large.png');
    File('assets/images/logo_medium.png').copySync('../assets/assets/images/logo_medium.png');
    File('assets/images/logo_small.png').copySync('../assets/assets/images/logo_small.png');
    
    File('web/icons/Icon-512.png').copySync('../icons/Icon-512.png');
    File('web/icons/Icon-192.png').copySync('../icons/Icon-192.png');
    File('web/icons/Icon-maskable-512.png').copySync('../icons/Icon-maskable-512.png');
    File('web/icons/Icon-maskable-192.png').copySync('../icons/Icon-maskable-192.png');
    
    // Copy favicon
    if (File('web/favicon.png').existsSync()) {
      File('web/favicon.png').copySync('../favicon.png');
    }
    
    print('Successfully copied all generated assets to outer folders!');
  } catch (e) {
    print('Warning: Failed to copy to outer deploy directories: $e');
  }

  print('DONE! Circular masking & PWA icon generation complete!');
}
