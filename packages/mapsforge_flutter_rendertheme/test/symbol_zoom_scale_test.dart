import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// twdcompass#923 — symbols and line symbols keep their size at every
/// zoomlevel, as in Java mapsforge; strokes still grow.
void main() {
  XmlElement element(String xml) => XmlDocument.parse(xml).rootElement;

  test('a symbol is as big at zoomlevel 20 as at 17', () {
    final symbol = RenderinstructionSymbol(0)..parse(element('<symbol src="x.svg" symbol-width="24" symbol-height="20"/>'));
    expect(MapsforgeSettingsMgr().strokeMinZoomlevelText, lessThanOrEqualTo(20));
    for (final zoom in [17, 18, 19, 20]) {
      final scaled = symbol.forZoomlevel(zoom, 0);
      expect(scaled.getBitmapWidth(), 24, reason: 'zoomlevel $zoom');
      expect(scaled.getBitmapHeight(), 20, reason: 'zoomlevel $zoom');
    }
  });

  test('a line symbol too', () {
    final symbol = RenderinstructionLinesymbol(0)..parse(element('<lineSymbol src="x.svg" symbol-width="16" symbol-height="16"/>'));
    for (final zoom in [17, 18, 19, 20]) {
      final scaled = symbol.forZoomlevel(zoom, 0);
      expect(scaled.getBitmapWidth(), 16, reason: 'zoomlevel $zoom');
      expect(scaled.getBitmapHeight(), 16, reason: 'zoomlevel $zoom');
    }
  });
}
