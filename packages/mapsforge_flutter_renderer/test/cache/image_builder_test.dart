import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter_renderer/src/cache/image_builder.dart';
import 'package:mapsforge_flutter_renderer/src/ui/symbol_image.dart';

/// Left half opaque black, right half empty, in a [viewBox]-unit square
/// declared the way `s_trailhead.svg` of the Rudy map theme does it.
Uint8List _halfSvg(int viewBox) => Uint8List.fromList(
  utf8.encode(
    '<svg width="100%" height="100%" viewBox="0 0 $viewBox $viewBox" '
    'xmlns="http://www.w3.org/2000/svg">'
    '<rect x="0" y="0" width="${viewBox / 2}" height="$viewBox" fill="#000000"/>'
    '</svg>',
  ),
);

Future<List<int>> _alphaRow(SymbolImage symbol, int y) async {
  final ui.Image image = symbol.expose();
  final ByteData data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return [for (int x = 0; x < image.width; x++) data.getUint8((y * image.width + x) * 4 + 3)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ImageBuilder builder = ImageBuilder();

  testWidgets('a small SVG is rasterised at the target size, not upscaled: the edge stays sharp', (tester) async {
    await tester.runAsync(() async {
      final SymbolImage symbol = await builder.createSvgSymbol(_halfSvg(10), 44, 44);
      expect(symbol.getWidth(), 44);
      expect(symbol.getHeight(), 44);
      final List<int> alpha = await _alphaRow(symbol, 22);
      // Drawn at 10×10 and resized, the edge at x = 22 smears over several
      // columns of partial alpha; drawn at 44×44 it is one pixel boundary.
      expect(alpha.sublist(0, 22), everyElement(255));
      expect(alpha.sublist(22), everyElement(0));
      symbol.dispose();
    });
  });

  testWidgets('a large SVG is drawn straight at the target size too', (tester) async {
    await tester.runAsync(() async {
      final SymbolImage symbol = await builder.createSvgSymbol(_halfSvg(580), 40, 40);
      expect(symbol.getWidth(), 40);
      expect(symbol.getHeight(), 40);
      final List<int> alpha = await _alphaRow(symbol, 20);
      expect(alpha.sublist(0, 20), everyElement(255));
      expect(alpha.sublist(20), everyElement(0));
      symbol.dispose();
    });
  });

  testWidgets('without a size the intrinsic size is kept', (tester) async {
    await tester.runAsync(() async {
      final SymbolImage symbol = await builder.createSvgSymbol(_halfSvg(24), 0, 0);
      expect(symbol.getWidth(), 24);
      expect(symbol.getHeight(), 24);
      symbol.dispose();
    });
  });
}
