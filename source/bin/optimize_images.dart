import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  final imageDir = Directory('assets/images');
  if (!await imageDir.exists()) {
    print('Error: assets/images directory not found');
    return;
  }

  final files = await imageDir.list().toList();
  final targetImages = [
    'andolan.jpg',
    'conference.jpg',
    'dharna.jpg',
    'meeting.jpg',
    'other.jpg',
    'protest.jpg',
    'rally.jpg'
  ];

  for (var entity in files) {
    if (entity is File) {
      final fileName = entity.path.split(Platform.pathSeparator).last;
      if (targetImages.contains(fileName)) {
        print('Processing $fileName...');
        
        final bytes = await entity.readAsBytes();
        final image = img.decodeImage(bytes);
        
        if (image == null) {
          print('Failed to decode $fileName');
          continue;
        }

        // Resize to 512x512 as requested
        print('Resizing $fileName to 512x512');
        img.Image optimized = img.copyResize(image, width: 512, height: 512);


        final optimizedBytes = img.encodeJpg(optimized, quality: 70);
        final newPath = entity.path; // Overwrite the same file
        
        await File(newPath).writeAsBytes(optimizedBytes);
        print('Saved optimized image to $newPath');
        
        // No need to delete original as we overwrote it
        // print('Deleted original $fileName');
      }
    }
  }
  print('Done!');
}
