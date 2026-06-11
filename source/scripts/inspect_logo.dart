import 'dart:io';
import 'package:image/image.dart';

void main() {
  final file = File('assets/images/app_icon.png');
  if (!file.existsSync()) {
    print('app_icon.png not found');
    return;
  }
  
  final bytes = file.readAsBytesSync();
  final image = decodeImage(bytes);
  if (image == null) {
    print('Failed to decode image');
    return;
  }
  
  print('Diagonal line scan from (0,0) to (150,150):');
  for (int i = 0; i < 150; i++) {
    final pixel = image.getPixel(i, i);
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();
    final a = pixel.a.toInt();
    print('i=$i: #Hex=${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')} ($a)');
  }
}
