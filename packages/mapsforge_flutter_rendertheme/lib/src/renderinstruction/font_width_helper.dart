import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';

class FontWidthHelper {
  /// Calculates boundary with estimated text width based on actual text content.
  ///
  /// This method provides more accurate boundary calculations by estimating
  /// the actual text width using Flutter's TextPainter. Falls back to
  /// maxTextWidth if text is not available or measurement fails.
  ///
  /// [text] The text content to measure
  MapSize getBoundaryForText(
    String text,
    MapFontFamily fontFamily,
    MapFontStyle fontStyle,
    double fontSize,
    double strokeWidth,
    double maxTextLength,
  ) {
    if (text.isEmpty) return const MapSize.empty();

    // Average character width as fraction of font size
    // Monospace: ~0.6, Sans-serif: ~0.5, Serif: ~0.55
    double charWidthFactor = _getCharacterWidthFactor(fontFamily);

    // Account for font weight (bold text is wider)
    double weightMultiplier = fontStyle == MapFontStyle.BOLD || fontStyle == MapFontStyle.BOLD_ITALIC ? 1.1 : 1.0;

    // Add stroke padding if present
    double strokePadding = strokeWidth * 2;

    double width = text.length * fontSize * charWidthFactor * weightMultiplier + strokePadding;

    int lines = (width / maxTextLength).ceil();
    if (lines > 1) {
      width = maxTextLength + strokePadding;
    }
    return MapSize(width: width, height: (fontSize + strokePadding) * lines);
  }

  /// Estimated size of a text drawn along a way (one line). Unlike [getBoundaryForText] it weighs the characters by
  /// kind: digits are narrow (measured 0.56 em in Roboto, 0.62 em in SF), CJK characters take a full em, everything
  /// else keeps the 0.9 em of [getBoundaryForText].
  MapSize getBoundaryForPathText(String text, MapFontStyle fontStyle, double fontSize, double strokeWidth) {
    if (text.isEmpty) return const MapSize.empty();
    double ems = 0;
    for (int rune in text.runes) {
      if (rune >= 0x30 && rune <= 0x39) {
        ems += 0.63;
      } else if (rune >= 0x2E80) {
        ems += 1.0;
      } else {
        ems += 0.9;
      }
    }
    double weightMultiplier = fontStyle == MapFontStyle.BOLD || fontStyle == MapFontStyle.BOLD_ITALIC ? 1.1 : 1.0;
    double strokePadding = strokeWidth * 2;
    return MapSize(width: ems * fontSize * weightMultiplier + strokePadding, height: fontSize + strokePadding);
  }

  /// Gets the font family name for TextStyle creation.
  // String _getFontFamilyName() {
  //   switch (fontFamily) {
  //     case MapFontFamily.DEFAULT:
  //       return 'Roboto';
  //     case MapFontFamily.MONOSPACE:
  //       return 'Courier New';
  //     case MapFontFamily.SANS_SERIF:
  //       return 'Arial';
  //     case MapFontFamily.SERIF:
  //       return 'Times New Roman';
  //   }
  // }

  /// Gets the FontStyle for TextStyle creation.
  // ui.FontStyle _getFontStyle() {
  //   switch (fontStyle) {
  //     case MapFontStyle.ITALIC:
  //     case MapFontStyle.BOLD_ITALIC:
  //       return ui.FontStyle.italic;
  //     default:
  //       return ui.FontStyle.normal;
  //   }
  // }

  /// Gets character width factor based on font family.
  double _getCharacterWidthFactor(MapFontFamily fontFamily) {
    switch (fontFamily) {
      case MapFontFamily.MONOSPACE:
        return 0.9; // Monospace characters are wider
      case MapFontFamily.SERIF:
        return 0.9; // Serif fonts are slightly wider
      case MapFontFamily.SANS_SERIF:
      case MapFontFamily.DEFAULT:
        return 0.9; // Sans-serif average
    }
  }
}
