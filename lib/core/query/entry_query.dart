class EntryQuery {
  static const Object _unset = Object();

  final DateTime? from;
  final DateTime? to;
  final Set<String> entryTypes;
  final Set<String> domains;
  final Set<String> categoryL1;
  final Set<String> categoryL2;
  final Set<String> subjectNames;
  final Set<String> tags;
  final String? keyword;
  final bool? confirmedOnly;
  final String sortBy;
  final bool descending;
  final int? limit;
  final int? offset;

  const EntryQuery({
    this.from,
    this.to,
    this.entryTypes = const <String>{},
    this.domains = const <String>{},
    this.categoryL1 = const <String>{},
    this.categoryL2 = const <String>{},
    this.subjectNames = const <String>{},
    this.tags = const <String>{},
    this.keyword,
    this.confirmedOnly,
    this.sortBy = 'occurred_date',
    this.descending = true,
    this.limit,
    this.offset,
  });

  EntryQuery copyWith({
    Object? from = _unset,
    Object? to = _unset,
    Set<String>? entryTypes,
    Set<String>? domains,
    Set<String>? categoryL1,
    Set<String>? categoryL2,
    Set<String>? subjectNames,
    Set<String>? tags,
    Object? keyword = _unset,
    Object? confirmedOnly = _unset,
    String? sortBy,
    bool? descending,
    Object? limit = _unset,
    Object? offset = _unset,
  }) {
    return EntryQuery(
      from: identical(from, _unset) ? this.from : from as DateTime?,
      to: identical(to, _unset) ? this.to : to as DateTime?,
      entryTypes: entryTypes ?? this.entryTypes,
      domains: domains ?? this.domains,
      categoryL1: categoryL1 ?? this.categoryL1,
      categoryL2: categoryL2 ?? this.categoryL2,
      subjectNames: subjectNames ?? this.subjectNames,
      tags: tags ?? this.tags,
      keyword: identical(keyword, _unset) ? this.keyword : keyword as String?,
      confirmedOnly: identical(confirmedOnly, _unset)
          ? this.confirmedOnly
          : confirmedOnly as bool?,
      sortBy: sortBy ?? this.sortBy,
      descending: descending ?? this.descending,
      limit: identical(limit, _unset) ? this.limit : limit as int?,
      offset: identical(offset, _unset) ? this.offset : offset as int?,
    );
  }
}
