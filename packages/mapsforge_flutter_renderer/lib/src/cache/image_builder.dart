import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:mapsforge_flutter_renderer/src/ui/symbol_image.dart';

/// A utility class for creating `SymbolImage` objects from raw byte data.
///
/// This class handles the decoding and resizing of PNG and SVG images.
class ImageBuilder {
  const ImageBuilder();

  /// Creates a `SymbolImage` from PNG data.
  ///
  /// If [width] and [height] are specified, the image is resized to the given
  /// dimensions.
  ///
  /// When using this in tests, ensure it runs in a real async zone, for example
  /// by wrapping it with `tester.runAsync()`.
  Future<SymbolImage> createPngSymbol(Uint8List bytes, int width, int height) async {
    if (width != 0 && height != 0) {
      var codec = await ui.instantiateImageCodec(bytes, targetHeight: height, targetWidth: width);
      // add additional checking for number of frames etc here
      var frame = await codec.getNextFrame();
      ui.Image img = frame.image;

      SymbolImage result = SymbolImage(img);
      return result;
    } else {
      var codec = await ui.instantiateImageCodec(bytes);
      // add additional checking for number of frames etc here
      var frame = await codec.getNextFrame();
      ui.Image img = frame.image;

      SymbolImage result = SymbolImage(img);
      return result;
    }
  }

  /// Creates a `SymbolImage` from SVG data.
  ///
  /// When [width] and [height] are specified, the SVG is rasterised once,
  /// directly at that size. Drawing it at its intrinsic size first and
  /// resizing the bitmap afterwards blurs every SVG whose intrinsic size is
  /// smaller than the target — e.g. a `viewBox="0 0 10 10"` symbol shown
  /// 16 px wide on a 2.75× screen is upscaled more than fourfold. Without a
  /// size, the SVG is drawn at its intrinsic size.
  ///
  /// When using this in tests, ensure it runs in a real async zone, for example
  /// by wrapping it with `tester.runAsync()`.
  Future<SymbolImage> createSvgSymbol(Uint8List bytes, int width, int height) async {
    PictureInfo pictureInfo = await vg.loadPicture(SvgBytesLoader(bytes), null);
    try {
      final ui.Size size = pictureInfo.size;
      if (width == 0 || height == 0) {
        return SymbolImage(await pictureInfo.picture.toImage(size.width.round(), size.height.round()));
      }
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      if (!size.isEmpty) canvas.scale(width / size.width, height / size.height);
      canvas.drawPicture(pictureInfo.picture);
      final ui.Picture scaled = recorder.endRecording();
      try {
        return SymbolImage(await scaled.toImage(width, height));
      } finally {
        scaled.dispose();
      }
    } finally {
      pictureInfo.picture.dispose();
    }
  }
}
