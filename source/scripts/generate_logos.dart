import 'dart:io';
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

  if (image.numChannels < 4 || !image.hasAlpha) {
    image = image.convert(numChannels: 4);
  }

  // Generate Logo Small (128x128)
  final logoSmall = copyResize(image, width: 128, height: 128, interpolation: Interpolation.average);
  File('assets/images/logo_small.png').writeAsBytesSync(encodePng(logoSmall));
  print('Generated logo_small.png (128x128)');

  // Generate Logo Medium (256x256)
  final logoMedium = copyResize(image, width: 256, height: 256, interpolation: Interpolation.average);
  File('assets/images/logo_medium.png').writeAsBytesSync(encodePng(logoMedium));
  print('Generated logo_medium.png (256x256)');

  // Generate Logo Large (512x512)
  final logoLarge = copyResize(image, width: 512, height: 512, interpolation: Interpolation.average);
  File('assets/images/logo_large.png').writeAsBytesSync(encodePng(logoLarge));
  print('Generated logo_large.png (512x512)');

  // Splash Launch Image Resizing
  final splashLaunch = copyResize(image, width: 256, height: 256, interpolation: Interpolation.average);
  File('android/app/src/main/res/drawable/launch_image_small.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(encodePng(splashLaunch));
  print('Generated native launch_image_small.png (256x256)');

  print('Successfully generated all optimized logo sizes!');
}
