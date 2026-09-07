import 'package:xml/xml.dart';

/// The `<stylemenu>` of a render theme.
///
/// A style menu lists the selectable styles of a theme and the overlays each
/// style is composed of. Every `<layer>` carries a set of categories (`<cat>`);
/// a `<rule cat="...">` is only used when its category is enabled by the
/// selected style. This mirrors `XmlRenderThemeStyleMenu` of mapsforge (Java).
///
/// ```xml
/// <stylemenu id="menu" defaultvalue="hiking" defaultlang="en">
///   <layer id="contours" enabled="true"><cat id="contour"/></layer>
///   <layer id="hiking" visible="true">
///     <cat id="hike"/>
///     <overlay id="contours"/>
///   </layer>
/// </stylemenu>
/// ```
class RenderthemeStyleMenu {
  /// Identifier of the menu.
  final String id;

  /// Id of the layer selected when the caller does not pick a style.
  final String defaultValue;

  /// Language used for the layer titles when no better match exists.
  final String defaultLanguage;

  final Map<String, RenderthemeStyleLayer> _layers = {};

  RenderthemeStyleMenu({required this.id, required this.defaultValue, required this.defaultLanguage});

  /// All layers in document order, overlays included.
  List<RenderthemeStyleLayer> get layers => List.unmodifiable(_layers.values);

  RenderthemeStyleLayer? getLayer(String id) => _layers[id];

  /// Layers a user can choose as a style, i.e. those marked `visible="true"`.
  List<RenderthemeStyleLayer> get visibleLayers => _layers.values.where((layer) => layer.visible).toList();

  /// Returns the categories rendered for the style [styleId].
  ///
  /// These are the categories of the layer itself (including those inherited
  /// from its `parent`) plus the categories of its enabled overlays. An overlay
  /// is enabled when the theme declares it `enabled="true"`; [enabledOverlays]
  /// and [disabledOverlays] (overlay layer ids) switch individual overlays on
  /// or off in addition to that default, e.g. from a user's style settings.
  /// [disabledOverlays] wins over [enabledOverlays].
  ///
  /// Returns null if [styleId] does not name a layer of this menu.
  Set<String>? categoriesFor(String styleId, {Set<String> enabledOverlays = const {}, Set<String> disabledOverlays = const {}}) {
    RenderthemeStyleLayer? layer = _layers[styleId];
    if (layer == null) return null;
    Set<String> result = {...layer.categories};
    for (RenderthemeStyleLayer overlay in layer.overlays) {
      bool enabled = (overlay.enabled || enabledOverlays.contains(overlay.id)) && !disabledOverlays.contains(overlay.id);
      if (enabled) result.addAll(overlay.categories);
    }
    return result;
  }

  /// Parses a `<stylemenu>` element.
  ///
  /// A `parent` layer and an `<overlay>` must be declared before the layer
  /// referencing them (as in mapsforge); unknown references are ignored.
  static RenderthemeStyleMenu parse(XmlElement element) {
    String? id = element.getAttribute("id");
    String? defaultValue = element.getAttribute("defaultvalue");
    String? defaultLanguage = element.getAttribute("defaultlang");
    if (id == null || defaultValue == null || defaultLanguage == null) {
      throw Exception("stylemenu needs id, defaultvalue and defaultlang: $element");
    }
    RenderthemeStyleMenu menu = RenderthemeStyleMenu(id: id, defaultValue: defaultValue, defaultLanguage: defaultLanguage);
    for (XmlElement layerElement in element.childElements) {
      if (layerElement.name.local != "layer") continue;
      RenderthemeStyleLayer layer = RenderthemeStyleLayer._parse(layerElement, menu);
      menu._layers[layer.id] = layer;
    }
    if (menu._layers[defaultValue] == null) {
      throw Exception("stylemenu defaultvalue $defaultValue is not a layer");
    }
    return menu;
  }

  @override
  String toString() {
    return 'RenderthemeStyleMenu{id: $id, defaultValue: $defaultValue, layers: ${_layers.keys.toList()}}';
  }
}

/////////////////////////////////////////////////////////////////////////////

/// One `<layer>` of a [RenderthemeStyleMenu]: a selectable style or an overlay.
class RenderthemeStyleLayer {
  final String id;

  /// Whether this overlay is switched on by default.
  final bool enabled;

  /// Whether the layer is offered as a style (`true`) or is only an overlay.
  final bool visible;

  /// Categories of this layer, including those of its `parent` layer.
  final Set<String> categories;

  /// Overlays of this layer, including those of its `parent` layer.
  final List<RenderthemeStyleLayer> overlays;

  /// Titles by language code (`<name lang="en" value="Hiking"/>`).
  final Map<String, String> titles;

  RenderthemeStyleLayer({
    required this.id,
    required this.enabled,
    required this.visible,
    required this.categories,
    required this.overlays,
    required this.titles,
  });

  /// The title in [language], falling back to the menu's default language.
  String? getTitle(String language, RenderthemeStyleMenu menu) => titles[language] ?? titles[menu.defaultLanguage];

  static RenderthemeStyleLayer _parse(XmlElement element, RenderthemeStyleMenu menu) {
    String? id = element.getAttribute("id");
    if (id == null) throw Exception("layer needs an id: $element");
    bool enabled = element.getAttribute("enabled") == "true";
    bool visible = element.getAttribute("visible") == "true";
    Set<String> categories = {};
    List<RenderthemeStyleLayer> overlays = [];
    Map<String, String> titles = {};

    String? parentId = element.getAttribute("parent");
    if (parentId != null) {
      RenderthemeStyleLayer? parent = menu.getLayer(parentId);
      if (parent != null) {
        categories.addAll(parent.categories);
        overlays.addAll(parent.overlays);
      }
    }

    for (XmlElement child in element.childElements) {
      switch (child.name.local) {
        case "cat":
          String? catId = child.getAttribute("id");
          if (catId != null) categories.add(catId);
        case "overlay":
          String? overlayId = child.getAttribute("id");
          RenderthemeStyleLayer? overlay = overlayId == null ? null : menu.getLayer(overlayId);
          if (overlay != null) overlays.add(overlay);
        case "name":
          String? lang = child.getAttribute("lang");
          String? value = child.getAttribute("value");
          if (lang != null && value != null) titles[lang] = value;
      }
    }
    return RenderthemeStyleLayer(id: id, enabled: enabled, visible: visible, categories: categories, overlays: overlays, titles: titles);
  }

  @override
  String toString() {
    return 'RenderthemeStyleLayer{id: $id, enabled: $enabled, visible: $visible, categories: $categories, overlays: ${overlays.map((o) => o.id).toList()}}';
  }
}
