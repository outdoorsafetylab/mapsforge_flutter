import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_rendertheme/src/matcher/attributematcher.dart';
import 'package:mapsforge_flutter_rendertheme/src/matcher/indoornotationmatcher.dart';

import 'rule.dart';

class NegativeRule extends Rule {
  final AttributeMatcher attributeMatcher;

  NegativeRule({
    required this.attributeMatcher,
    required super.zoomlevelRange,
    required super.subRules,
    required super.renderinstructionNodes,
    required super.renderinstructionOpenWays,
    required super.renderinstructionClosedWays,
    super.cat,
  });

  @override
  NegativeRule? forZoomlevel(int zoomlevel, Set<String>? categories, int Function() getMaxLevel, {bool inContour = false}) {
    if (categories != null && cat != null && !categories.contains(cat)) return null;
    bool contour = isContour(inContour);
    var instructions = instructionsForZoomlevel(zoomlevel, getMaxLevel, contour);
    if (instructions == null) return null;
    var (nodes: renderinstructionNodes, openWays: renderinstructionOpenWays, closedWays: renderinstructionClosedWays) = instructions;
    List<Rule> subRules = [];
    for (var subRule in super.subRules) {
      Rule? rule = subRule.forZoomlevel(zoomlevel, categories, getMaxLevel, inContour: contour);
      if (rule != null) subRules.add(rule);
    }

    if (subRules.isEmpty && renderinstructionNodes.isEmpty && renderinstructionOpenWays.isEmpty && renderinstructionClosedWays.isEmpty) return null;
    return NegativeRule(
      attributeMatcher: attributeMatcher,
      zoomlevelRange: ZoomlevelRange(zoomlevel, zoomlevel),
      subRules: subRules,
      renderinstructionNodes: renderinstructionNodes,
      renderinstructionOpenWays: renderinstructionOpenWays,
      renderinstructionClosedWays: renderinstructionClosedWays,
    );
  }

  @override
  bool matchesForZoomLevel(int zoomlevel) {
    return zoomlevelRange.matches(zoomlevel);
  }

  @override
  bool matches(TagCollection tags, int indoorLevel) {
    return IndoorNotationMatcher.isOutdoorOrMatchesIndoorLevel(tags, indoorLevel) && attributeMatcher.matchesTagList(tags);
  }

  @override
  bool matchesTags(ITagCollection tags) {
    return attributeMatcher.matchesTagList(tags);
  }

  @override
  String toString() {
    return 'NegativeRule{attributeMatcher: $attributeMatcher, super: ${super.toString()}}';
  }
}
