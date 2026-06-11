import 'dart:io';
import 'package:image/image.dart';

void main() {
  final patrons = [
    'assets/images/patron1.jpg',
    'assets/images/patron2.jpg',
    'assets/images/patron3.jpg',
    'assets/images/patron4.jpg',
  ];

  for (final path in patrons) {
    final file = File(path);
    if (!file.existsSync()) {
      print('Warning: File not found at $path. Skipping...');
      continue;
    }

    final bytes = file.readAsBytesSync();
    final image = decodeImage(bytes);
    if (image == null) {
      print('Error: Could not decode image at $path');
      continue;
    }

    // Resize to exactly 128x128
    print('Original dimensions for $path: ${image.width}x${image.height}');
    final resized = copyResize(
      image,
      width: 128,
      height: 128,
      interpolation: Interpolation.average,
    );

    // Save back as JPG
    file.writeAsBytesSync(encodeJpg(resized, quality: 90));
    print('Successfully resized $path to 128x128');
  }

  print('Patron images resizing process completed!');
}
