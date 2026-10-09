import 'package:ecache/ecache.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';
import 'package:mapsforge_flutter_rendertheme/src/matcher/anymatcher.dart';
import 'package:mapsforge_flutter_rendertheme/src/matcher/attributematcher.dart';
import 'package:mapsforge_flutter_rendertheme/src/matcher/keymatcher.dart';
import 'package:mapsforge_flutter_rendertheme/src/matcher/negativematcher.dart';
import 'package:mapsforge_flutter_rendertheme/src/matcher/valuematcher.dart';
import 'package:mapsforge_flutter_rendertheme/src/model/matching_cache_key.dart';
import 'package:mapsforge_flutter_rendertheme/src/rule/negativerule.dart';
import 'package:mapsforge_flutter_rendertheme/src/rule/positiverule.dart';

/// Zoom level specific rendering theme containing optimized rule matching.
///
/// This class represents a pre-processed rendering theme for a specific zoom level,
/// providing cached rule matching for improved performance. It maintains separate
/// caches for nodes, open ways, and closed ways to optimize rendering operations.
///
/// Key features:
/// - LRU caches for rule matching results
/// - Separate handling for nodes, open ways, and closed ways
/// - Indoor level support for 3D mapping
/// - Optimized matching algorithms with caching
class RenderthemeZoomlevel {
  /// Hierarchical list of rendering rules for this zoom level.
  ///
  /// Contains the complete rule tree structure as defined in the theme XML,
  /// organized for efficient matching against map features.
  final List<Rule> rulesList;

  /// LRU cache for node (POI) rendering instruction matches.
  late final Cache<MatchingCacheKey, List<Renderinstruction>> nodeMatchingCache;

  /// LRU cache for open way (linear) rendering instruction matches.
  late final Cache<MatchingCacheKey, List<Renderinstruction>> openWayMatchingCache;

  /// LRU cache for closed way (area) rendering instruction matches.
  late final Cache<MatchingCacheKey, List<Renderinstruction>> closedWayMatchingCache;

  int maxLevels;

  /// What the rules of this zoom level look at, see [_cacheKey]; null if a rule uses a matcher we do not know, then
  /// the cache is keyed by all tags.
  late final _RuleAttributes? _attributes = _RuleAttributes.of(rulesList);

  /// Creates a new zoom level specific rendering theme.
  ///
  /// [rulesList] Hierarchical list of rendering rules for this zoom level
  RenderthemeZoomlevel({required this.rulesList, required this.maxLevels, int zoomlevel = -1}) {
    nodeMatchingCache = LruCache(capacity: 1000, name: "Node-MatchingCache$zoomlevel");
    openWayMatchingCache = LruCache(capacity: 5000, name: "OpenWay-MatchingCache$zoomlevel");
    closedWayMatchingCache = LruCache(capacity: 2000, name: "ClosedWay-MatchingCache$zoomlevel");
  }

  void dispose() {
    rulesList.clear();
    nodeMatchingCache.dispose();
    openWayMatchingCache.dispose();
    closedWayMatchingCache.dispose();
  }

  /// Matches a node (POI) against the rendering rules for this zoom level.
  ///
  /// Uses cached results when available to improve performance. The matching
  /// process considers both the POI's tags and the indoor level for 3D mapping.
  ///
  /// [indoorLevel] Indoor level for 3D mapping support
  /// [pointOfInterest] Point of interest to match against rules
  /// Returns list of applicable rendering instructions
  List<Renderinstruction> matchNode(final int indoorLevel, PointOfInterest pointOfInterest) {
    MatchingCacheKey matchingCacheKey = _cacheKey(pointOfInterest.tags, indoorLevel);

    List<Renderinstruction>? matchingList = nodeMatchingCache[matchingCacheKey];
    if (matchingList == null) {
      // build cache
      matchingList = [];

      for (var element in rulesList) {
        element.matchNode(indoorLevel, matchingList, pointOfInterest);
      }
      nodeMatchingCache[matchingCacheKey] = matchingList;
    }
    return matchingList;
  }

  /// Matches a closed way (area) against the rendering rules for this zoom level.
  ///
  /// Uses cached results when available to improve performance. Closed ways
  /// represent areas such as buildings, parks, or water bodies.
  ///
  /// [tile] Tile context containing indoor level information
  /// [way] Closed way to match against rules
  /// Returns list of applicable rendering instructions
  List<Renderinstruction> matchClosedWay(final Tile tile, Way way) {
    MatchingCacheKey matchingCacheKey = _cacheKey(way.tags, tile.indoorLevel);

    List<Renderinstruction>? matchingList = closedWayMatchingCache[matchingCacheKey];
    if (matchingList == null) {
      // build cache
      matchingList = [];
      for (var rule in rulesList) {
        rule.matchClosedWay(way, tile, matchingList);
      }

      closedWayMatchingCache[matchingCacheKey] = matchingList;
    }
    return matchingList;
  }

  /// Matches a linear way (open path) against the rendering rules for this zoom level.
  ///
  /// Uses cached results when available to improve performance. Linear ways
  /// represent paths such as roads, rivers, or boundaries.
  ///
  /// [tile] Tile context containing indoor level information
  /// [way] Linear way to match against rules
  /// Returns list of applicable rendering instructions
  List<Renderinstruction> matchOpenWay(final Tile tile, Way way) {
    MatchingCacheKey matchingCacheKey = _cacheKey(way.tags, tile.indoorLevel);

    List<Renderinstruction>? matchingList = openWayMatchingCache[matchingCacheKey];
    if (matchingList == null) {
      // build cache
      matchingList = [];
      for (var rule in rulesList) {
        rule.matchOpenWay(way, tile, matchingList);
      }

      openWayMatchingCache[matchingCacheKey] = matchingList;
    }
    return matchingList;
  }

  /// The cache key for [tags]: only what the rules can tell apart.
  ///
  /// A rule matches by which of its keys are present, which of its values are present (on any key, as in mapsforge)
  /// and, for the indoor level, the values of `level` and `repeat_on`. Keying the cache by all tags made every named
  /// feature a key of its own: in Taipei at zoom 14 a block of 40,000 POIs had 18,000 different keys, and the node
  /// cache of 1000 entries missed nearly every time. Keyed by what the rules see, the same block has 194.
  MatchingCacheKey _cacheKey(ITagCollection tags, int indoorLevel) {
    _RuleAttributes? attributes = _attributes;
    if (attributes == null || tags is! TagCollection) return MatchingCacheKey(tags, indoorLevel);
    List<Tag> seen = [];
    bool same = true;
    for (Tag tag in tags.tags) {
      if (attributes.values.contains(tag.value) || _RuleAttributes.indoorKeys.contains(tag.key)) {
        seen.add(tag);
      } else if (attributes.keys.contains(tag.key)) {
        seen.add(Tag(tag.key, attributes.present));
        same = false;
      } else {
        same = false;
      }
    }
    return MatchingCacheKey(same ? tags : TagCollection(tags: seen), indoorLevel);
  }
}

/// The tag keys and values the rules of a zoom level match against.
class _RuleAttributes {
  /// Read by the indoor level check of every rule ([IndoorNotationMatcher]), with their values.
  static const Set<String> indoorKeys = {'level', 'repeat_on'};

  /// Keys whose presence a rule checks.
  final Set<String> keys = {};

  /// Values whose presence (on any key) a rule checks.
  final Set<String> values = {};

  /// Stands for the value of a tag whose key matters but whose value does not; not in [values].
  late final String present;

  _RuleAttributes._();

  static _RuleAttributes? of(List<Rule> rules) {
    _RuleAttributes attributes = _RuleAttributes._();
    bool known = true;
    void addMatcher(AttributeMatcher matcher) {
      if (matcher is KeyMatcher) {
        attributes.keys.addAll(matcher.keys);
      } else if (matcher is ValueMatcher) {
        attributes.values.addAll(matcher.values);
      } else if (matcher is NegativeMatcher) {
        attributes.keys.addAll(matcher.keys);
        attributes.values.addAll(matcher.values);
      } else if (matcher is! AnyMatcher) {
        known = false;
      }
    }

    void addRule(Rule rule) {
      if (rule is PositiveRule) {
        addMatcher(rule.keyMatcher);
        addMatcher(rule.valueMatcher);
      } else if (rule is NegativeRule) {
        addMatcher(rule.attributeMatcher);
      } else {
        known = false;
      }
      rule.subRules.forEach(addRule);
    }

    rules.forEach(addRule);
    if (!known) return null;
    String present = '\u0000';
    while (attributes.values.contains(present)) {
      present += '\u0000';
    }
    attributes.present = present;
    return attributes;
  }
}
