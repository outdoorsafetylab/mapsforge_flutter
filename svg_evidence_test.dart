// Writes the before/after images of the PR "fix(renderer): rasterise SVG
// symbols at the target size". Copy into
// packages/mapsforge_flutter_renderer/test/ on the PR branch and run:
//   flutter test test/svg_evidence_test.dart --dart-define=OUT=/some/dir
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter_renderer/src/cache/image_builder.dart';

const String out = String.fromEnvironment('OUT');

// A 10×10 viewBox symbol, declared with width/height 100 %.
final Uint8List svg = Uint8List.fromList(utf8.encode(
  '<svg width="100%" height="100%" viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg">'
  '<circle cx="5" cy="5" r="4.5" fill="#ffffff" stroke="#b03a2e" stroke-width="0.8"/>'
  '<path d="M5 2 L7.6 7.5 L2.4 7.5 Z" fill="#b03a2e"/>'
  '<rect x="4.6" y="5.2" width="0.8" height="1.6" fill="#ffffff"/>'
  '</svg>'));

// The code path on master: intrinsic size, PNG, resized by the codec.
Future<ui.Image> master(int w, int h) async {
  final info = await vg.loadPicture(SvgBytesLoader(svg), null);
  final img = await info.picture.toImage(info.size.width.round(), info.size.height.round());
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  info.picture.dispose();
  final codec = await ui.instantiateImageCodec(png!.buffer.asUint8List(), targetWidth: w, targetHeight: h);
  return (await codec.getNextFrame()).image;
}

// Nearest-neighbour ×k so the pixels show.
Future<ui.Image> blowUp(ui.Image src, int k) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawColor(const ui.Color(0xFFE8E8E8), ui.BlendMode.src);
  c.scale(k.toDouble());
  c.drawImage(src, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.none);
  return rec.endRecording().toImage(src.width * k, src.height * k);
}

Future<void> save(ui.Image img, String name) async {
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  await File('$out/$name').writeAsBytes(png!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('before/after images', (tester) async {
    await tester.runAsync(() async {
      const size = 44; // a 16 dp symbol on a 2.75× screen
      final before = await master(size, size);
      final after = (await const ImageBuilder().createSvgSymbol(svg, size, size)).expose();
      await save(await blowUp(before, 6), 'svg-44px-master-x6.png');
      await save(await blowUp(after, 6), 'svg-44px-fix-x6.png');
    });
  });
}
