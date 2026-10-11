import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_rendertheme/src/matcher/attributematcher.dart';
import 'package:mapsforge_flutter_rendertheme/src/matcher/indoornotationmatcher.dart';

import 'rule.dart';

class PositiveRule extends Rule {
  final AttributeMatcher keyMatcher;
  final AttributeMatcher valueMatcher;

  PositiveRule({
    required this.keyMatcher,
    required this.valueMatcher,
    required super.zoomlevelRange,
    required super.subRules,
    required super.renderinstructionNodes,
    required super.renderinstructionOpenWays,
    required super.renderinstructionClosedWays,
    super.cat,
  });

  @override
  PositiveRule? forZoomlevel(int zoomlevel, Set<String>? categories, int Function() getMaxLevel, {bool inContour = false}) {
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
    return PositiveRule(
      keyMatcher: keyMatcher,
      valueMatcher: valueMatcher,
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
    return IndoorNotationMatcher.isOutdoorOrMatchesIndoorLevel(tags, indoorLevel) &&
        keyMatcher.matchesTagList(tags) &&
        valueMatcher.matchesTagList(tags);
  }

  @override
  bool matchesTags(ITagCollection tags) {
    return keyMatcher.matchesTagList(tags) && valueMatcher.matchesTagList(tags);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositiveRule && runtimeType == other.runtimeType && keyMatcher == other.keyMatcher && valueMatcher == other.valueMatcher;

  @override
  int get hashCode => keyMatcher.hashCode ^ valueMatcher.hashCode;

  @override
  String toString() {
    return 'PositiveRule{keyMatcher: $keyMatcher, valueMatcher: $valueMatcher, super: ${super.toString()}}';
  }
}
