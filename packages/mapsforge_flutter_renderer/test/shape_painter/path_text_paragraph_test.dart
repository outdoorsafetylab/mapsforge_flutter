import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_renderer/shape_painter.dart';
import 'package:mapsforge_flutter_renderer/src/ui/ui_paint.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';

/// A text along a way collides with a box one line high, so it must be painted on one line however long it is.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = '''
<rendertheme xmlns="http://mapsforge.org/renderTheme" version="6">
  <rule e="way" k="highway" v="*">
    <pathText k="name" font-size="40" stroke-width="1"/>
  </rule>
</rendertheme>''';

  testWidgets('a long text along a way is laid out on one line', (tester) async {
    final level = RenderThemeBuilder.createFromString(theme).prepareZoomlevel(16);
    final way = Way(
      0,
      const [Tag('highway', 'path'), Tag('name', '一條名字很長很長很長的步道')],
      [
        [const LatLong(24.0, 121.0), const LatLong(24.0, 121.01)],
      ],
      null,
    );
    final instruction = level.matchOpenWay(Tile(0, 0, 16, 0), way).whereType<RenderinstructionPolylineText>().single;
    final painter = await ShapePainterPolylineText.create(instruction);

    final entry = painter.paragraphFor('一條名字很長很長很長的步道', UiPaint.fill(color: 0xff000000));
    // wider than the instruction's max text width, where it used to wrap
    expect(entry.getWidth(), greaterThan(instruction.getMaxTextWidth()));
    expect(entry.paragraph.computeLineMetrics(), hasLength(1));
  });
}
