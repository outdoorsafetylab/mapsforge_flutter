import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';
import 'package:mapsforge_flutter_rendertheme/src/renderinstruction/renderinstruction_hillshading.dart';
import 'package:mapsforge_flutter_rendertheme/src/xml/rulebuilder.dart';
import 'package:mapsforge_flutter_rendertheme/src/xml/xmlutils.dart';
import 'package:xml/xml.dart';

/// Builder class for parsing XML theme files and creating RenderTheme instances.
///
/// This class handles the parsing of XML-based rendering theme files, converting
/// them into structured RenderTheme objects. It supports theme customization through
/// element exclusion and provides comprehensive error handling during parsing.
///
/// Key features:
/// - XML theme file parsing and validation
/// - Rule hierarchy construction
/// - Element exclusion for theme customization
/// - Version compatibility checking
/// - Comprehensive error reporting
class RenderThemeBuilder {
  static final _log = Logger('RenderThemeBuilder');

  // XML attribute and element constants

  /// XML attribute for base stroke width scaling factor.
  static final String BASE_STROKE_WIDTH = "base-stroke-width";

  /// XML attribute for base text size scaling factor.
  static final String BASE_TEXT_SIZE = "base-text-size";

  /// XML attribute for map background color.
  static final String MAP_BACKGROUND = "map-background";

  /// XML attribute for background color outside map bounds.
  static final String MAP_BACKGROUND_OUTSIDE = "map-background-outside";

  /// Current supported render theme version.
  static final int RENDER_THEME_VERSION = 6;

  /// XML attribute for theme version.
  static final String VERSION = "version";

  /// XML namespace declaration.
  static final String XMLNS = "xmlns";

  /// XML Schema Instance namespace declaration.
  static final String XMLNS_XSI = "xmlns:xsi";

  /// XML Schema location attribute.
  static final String XSI_SCHEMALOCATION = "xsi:schemaLocation";

  /// Base stroke width scaling factor from theme definition.
  double baseStrokeWidth = 1;

  /// Base text size scaling factor from theme definition.
  double baseTextSize = 1;

  /// Whether the theme defines background color for areas outside the map.
  bool? hasBackgroundOutside;

  /// Map background color in ARGB format.
  int? mapBackground;

  /// Background color for areas outside map bounds in ARGB format.
  int? mapBackgroundOutside;

  /// Theme file version number.
  late int version;

  /// Stack of rule builders for hierarchical rule construction.
  final List<RuleBuilder> ruleBuilderStack = [];

  /// Current nesting level during XML parsing. Each rule gets a new level in ascending order from the
  /// top to the bottom of the rendertheme.xml file.
  int _level = -1;

  /// Hash string for theme identification and caching.
  String forHash = "";

  /// Set of element IDs to exclude from rendering for theme customization.
  final Set<String> excludeIds;

  /// The style to select from the theme's `<stylemenu>`; null selects the menu's `defaultvalue`.
  final String? styleId;

  /// Overlay ids of the selected style to switch on in addition to those the theme marks `enabled="true"`.
  final Set<String> enabledOverlays;

  /// Overlay ids of the selected style to switch off although the theme marks them `enabled="true"`.
  final Set<String> disabledOverlays;

  /// The parsed `<stylemenu>`, null if the theme has none.
  RenderthemeStyleMenu? styleMenu;

  /// Categories enabled by the selected style. Null if the theme has no `<stylemenu>`, in which case every rule is used.
  Set<String>? categories;

  /// Private constructor for creating builder instances.
  ///
  /// [excludeIds] Optional set of element IDs to exclude from rendering
  RenderThemeBuilder._({this.excludeIds = const {}, this.styleId, this.enabledOverlays = const {}, this.disabledOverlays = const {}});

  /// Creates a RenderTheme from XML content string.
  ///
  /// Parses the provided XML content and builds a complete RenderTheme object.
  /// Supports element exclusion for theme customization.
  ///
  /// [content] XML theme content as string
  /// [excludeIds] Optional set of element IDs to exclude from rendering
  /// [styleId] The style (a `<layer>` id) to select from the theme's `<stylemenu>`. Defaults to the
  /// menu's `defaultvalue`. Rules whose `cat` is not enabled by the style are not loaded. Ignored if
  /// the theme has no style menu.
  /// [enabledOverlays] Ids of overlays (`<overlay id=...>` layers) of the selected style to switch on
  /// in addition to those the theme marks `enabled="true"`.
  /// [disabledOverlays] Ids of overlays to switch off although the theme marks them `enabled="true"`.
  /// Returns the parsed RenderTheme
  /// Throws FormatException if XML parsing fails
  static Rendertheme createFromString(String content, {Set<String> excludeIds = const {}, String? styleId, Set<String> enabledOverlays = const {}, Set<String> disabledOverlays = const {}}) {
    RenderThemeBuilder renderThemeBuilder = RenderThemeBuilder._(excludeIds: excludeIds, styleId: styleId, enabledOverlays: enabledOverlays, disabledOverlays: disabledOverlays);
    renderThemeBuilder._parseXml(content);
    renderThemeBuilder.forHash =
        "${MapsforgeSettingsMgr().getUserScaleFactor()}_${MapsforgeSettingsMgr().getFontScaleFactor()}_${MapsforgeSettingsMgr().tileSize}";
    return renderThemeBuilder._build();
  }

  /// Builds and returns a rendertheme by loading a rendertheme file. This
  /// is a convienience-function. If desired we can also implement some caching
  /// so that we do not need to parse the same file over and over again.
  static Future<Rendertheme> createFromFile(
    String filename, {
    Set<String> excludeIds = const {},
    String? styleId,
    Set<String> enabledOverlays = const {},
    Set<String> disabledOverlays = const {},
  }) async {
    File file = File(filename);
    List<int> bytes = await file.readAsBytes();
    String content = const Utf8Decoder().convert(bytes);
    return RenderThemeBuilder.createFromString(content, excludeIds: excludeIds, styleId: styleId, enabledOverlays: enabledOverlays, disabledOverlays: disabledOverlays);
  }

  /// @return a new {@code RenderTheme} instance.
  Rendertheme _build() {
    // the stack is empty when the style or the overlays switch every top-level rule off, which is a valid
    // (if blank) theme
    List<Rule> rules = [];
    for (var ruleBuilder in ruleBuilderStack) {
      if (!ruleBuilder.impossible) {
        Rule? rule = ruleBuilder.build();
        if (rule == null) continue;
        rules.add(rule);
        rule.parent = null;
      }
    }
    Rendertheme renderTheme = Rendertheme(maxLevels: _level, rulesList: rules, styleMenu: styleMenu);
    for (Rule rule in rules) {
      rule.secondPass();
    }
    return renderTheme;
  }

  int getNextLevel() {
    ++_level;
    return _level;
  }

  /// A rule is visible if the theme has no style menu, the rule has no category
  /// or the selected style enables the rule's category.
  bool isVisibleRule(String? cat) {
    return categories == null || cat == null || categories!.contains(cat);
  }

  ///
  /// Parses a given xml string and creates the renderinstruction-structure. The renderinstruction classes serves two purposes:
  /// On the one hand to parse the xml and create the tree structure and on the other hand to render ways and pois
  /// appropriately and draw the respective content.
  ///
  void _parseXml(String content) {
    assert(content.length > 10);
    int time = DateTime.now().millisecondsSinceEpoch;
    XmlDocument document = XmlDocument.parse(content);
    assert(document.children.isNotEmpty);
    bool foundRendertheme = false;
    for (XmlNode node in document.children) {
      switch (node.nodeType) {
        case XmlNodeType.TEXT:
          break;
        case XmlNodeType.PROCESSING:
          break;
        case XmlNodeType.ELEMENT:
          {
            XmlElement element = node as XmlElement;
            if (element.name.toString() != "rendertheme") throw Exception("Invalid root node ${element.name.toString()}");
            foundRendertheme = true;
            _parseRendertheme(element);
            break;
          }
        case XmlNodeType.ATTRIBUTE:
          throw Exception("Invalid node ${node.nodeType.toString()}");
        case XmlNodeType.CDATA:
          throw Exception("Invalid node ${node.nodeType.toString()}");
        case XmlNodeType.COMMENT:
          break;
        case XmlNodeType.DOCUMENT:
          throw Exception("Invalid node ${node.nodeType.toString()}");
        case XmlNodeType.DOCUMENT_FRAGMENT:
          throw Exception("Invalid node ${node.nodeType.toString()}");
        case XmlNodeType.DOCUMENT_TYPE:
          throw Exception("Invalid node ${node.nodeType.toString()}");
        case XmlNodeType.DECLARATION:
          break;
        default:
          break;
      }
    }
    assert(foundRendertheme);
    for (RuleBuilder ruleBuilder in ruleBuilderStack) {
      ruleBuilder.validateTree();
    }
    //_log.info("Found ${initPendings.length} items for lazy initialization");
  }

  void _parseRendertheme(XmlElement rootElement) {
    for (var attribute in rootElement.attributes) {
      String name = attribute.name.toString();
      String value = attribute.value;
      //_log.info("checking $name=$value");
      if (XMLNS == name) {
        continue;
      } else if (XMLNS_XSI == name) {
        continue;
      } else if (XSI_SCHEMALOCATION == name) {
        continue;
      } else if (VERSION == name) {
        version = int.parse(value);
        if (version > RENDER_THEME_VERSION) {
          throw Exception("unsupported render theme version: $version");
        }
      } else if (MAP_BACKGROUND == name) {
        //        this.mapBackground = XmlUtils.getColor(
        //            graphicFactory, value, displayModel.getThemeCallback(), null);
      } else if (MAP_BACKGROUND_OUTSIDE == name) {
        //        this.mapBackgroundOutside = XmlUtils.getColor(
        //            graphicFactory, value, displayModel.getThemeCallback(), null);
        hasBackgroundOutside = true;
      } else if (BASE_STROKE_WIDTH == name) {
        baseStrokeWidth = XmlUtils.parseNonNegativeFloat(name, value);
      } else if (BASE_TEXT_SIZE == name) {
        baseTextSize = XmlUtils.parseNonNegativeFloat(name, value);
      } else {
        throw Exception("$name=$value");
      }
    }
    assert(rootElement.children.isNotEmpty);
    // The style menu decides which rules are loaded, so resolve it before any rule is parsed
    // regardless of where the theme places it.
    for (XmlElement element in rootElement.childElements) {
      if (element.name.toString() == "stylemenu") {
        if (styleMenu != null) throw Exception("More than one stylemenu");
        styleMenu = RenderthemeStyleMenu.parse(element);
        String style = styleId ?? styleMenu!.defaultValue;
        categories = styleMenu!.categoriesFor(style, enabledOverlays: enabledOverlays, disabledOverlays: disabledOverlays);
        if (categories == null) throw Exception("Style $style is not a layer of stylemenu ${styleMenu!.id}");
      }
    }
    bool foundElement = false;
    for (XmlNode node in rootElement.children) {
      switch (node.nodeType) {
        case XmlNodeType.TEXT:
          break;
        case XmlNodeType.PROCESSING:
          break;
        case XmlNodeType.ELEMENT:
          {
            XmlElement element = node as XmlElement;
            foundElement = true;
            if (element.name.toString() == "rule") {
              if (!isVisibleRule(element.getAttribute(RuleBuilder.CAT))) break;
              // Pass the excludeIds from this builder into each new RuleBuilder.
              RuleBuilder ruleBuilder = RuleBuilder(this, excludeIds: excludeIds);
              ruleBuilder.parse(element);
              ruleBuilderStack.add(ruleBuilder);
              break;
            } else if ("hillshading" == element.name.toString()) {
              RenderinstructionHillshading hillshading = RenderinstructionHillshading(_level);
              hillshading.parse(element);

              //      if (this.categories == null || category == null || this.categories.contains(category)) {
              //hillShadings.add(hillshading);
              //      }
              //print("Time ${DateTime.now().millisecondsSinceEpoch - time} after hillshading");
              break;
            } else if ("stylemenu" == element.name.toString()) {
              // already parsed above
              break;
            }
            throw Exception("Invalid node ${element.name.toString()}");
          }
        case XmlNodeType.ATTRIBUTE:
          throw Exception("Invalid node ${node.nodeType.toString()}");
        case XmlNodeType.CDATA:
          throw Exception("Invalid node ${node.nodeType.toString()}");
        case XmlNodeType.COMMENT:
          break;
        case XmlNodeType.DOCUMENT:
          throw Exception("Invalid node ${node.nodeType.toString()}");
        case XmlNodeType.DOCUMENT_FRAGMENT:
          throw Exception("Invalid node ${node.nodeType.toString()}");
        case XmlNodeType.DOCUMENT_TYPE:
          throw Exception("Invalid node ${node.nodeType.toString()}");
        case XmlNodeType.DECLARATION:
          break;
        default:
          break;
      }
    }
    assert(foundElement);
  }
}
