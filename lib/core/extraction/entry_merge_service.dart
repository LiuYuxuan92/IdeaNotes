import 'extraction_models.dart';

class EntryMergeService {
  const EntryMergeService();

  List<ExtractedEntry> merge({
    required List<ExtractedEntry> ruleEntries,
    required List<ExtractedEntry> aiEntries,
  }) {
    final mergedByFingerprint = <String, ExtractedEntry>{};

    for (final aiEntry in aiEntries) {
      mergedByFingerprint[_fingerprint(aiEntry)] = aiEntry;
    }

    for (final ruleEntry in ruleEntries) {
      final key = _fingerprint(ruleEntry);
      final existing = mergedByFingerprint[key];
      if (existing == null) {
        mergedByFingerprint[key] = ruleEntry;
        continue;
      }
      mergedByFingerprint[key] = _mergePair(existing, ruleEntry);
    }

    final merged = mergedByFingerprint.values.toList(growable: false);
    merged.sort((left, right) {
      final dateCompare = right.occurredDate.compareTo(left.occurredDate);
      if (dateCompare != 0) return dateCompare;
      return left.title.compareTo(right.title);
    });
    return merged;
  }

  ExtractedEntry _mergePair(ExtractedEntry ai, ExtractedEntry rule) {
    final mergedTags =
        <String>{...ai.tags, ...rule.tags}.toList(growable: false);
    final mergedSubjects = _mergeSubjects(ai.subjects, rule.subjects);
    final mergedLinks = _mergeLinks(ai.links, rule.links);
    final mergedNormalized = Map<String, dynamic>.from(ai.normalized);
    for (final entry in rule.normalized.entries) {
      mergedNormalized.putIfAbsent(entry.key, () => entry.value);
    }

    return ai.copyWith(
      occurredAt: ai.occurredAt ?? rule.occurredAt,
      endAt: ai.endAt ?? rule.endAt,
      amount: ai.amount ?? rule.amount,
      category: ai.category ?? rule.category,
      summary: _pickPreferred(ai.summary, rule.summary),
      status: _pickStatus(ai.status, rule.status),
      tags: mergedTags,
      subjects: mergedSubjects,
      links: mergedLinks,
      normalized: mergedNormalized,
      confidence:
          ai.confidence >= rule.confidence ? ai.confidence : rule.confidence,
    );
  }

  List<ExtractionSubject> _mergeSubjects(
    List<ExtractionSubject> aiSubjects,
    List<ExtractionSubject> ruleSubjects,
  ) {
    final result = <String, ExtractionSubject>{};
    for (final item in [...aiSubjects, ...ruleSubjects]) {
      final key = '${item.type.toLowerCase()}|${item.name.toLowerCase()}';
      result.putIfAbsent(key, () => item);
    }
    return result.values.toList(growable: false);
  }

  List<ExtractionLink> _mergeLinks(
    List<ExtractionLink> aiLinks,
    List<ExtractionLink> ruleLinks,
  ) {
    final result = <String, ExtractionLink>{};
    for (final item in [...aiLinks, ...ruleLinks]) {
      final key = '${item.type}|${item.targetEntryTempId}';
      result.putIfAbsent(key, () => item);
    }
    return result.values.toList(growable: false);
  }

  String _fingerprint(ExtractedEntry entry) {
    final raw =
        entry.rawText.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final date = formatDateOnly(entry.occurredDate);
    return '${entry.entryType.toValue()}|${entry.domain}|$date|$raw';
  }

  String? _pickPreferred(String? primary, String? fallback) {
    if (primary != null && primary.trim().isNotEmpty) return primary;
    if (fallback != null && fallback.trim().isNotEmpty) return fallback;
    return null;
  }

  String _pickStatus(String aiStatus, String ruleStatus) {
    if (aiStatus.trim().isNotEmpty && aiStatus != 'recorded') {
      return aiStatus;
    }
    if (ruleStatus.trim().isNotEmpty) {
      return ruleStatus;
    }
    return aiStatus;
  }
}
