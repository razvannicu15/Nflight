import 'store.dart';

/// What is left of each data source's free allowance, as last reported.
class QuotaInfo {
  QuotaInfo({this.remaining, this.limit, this.resetAt, required this.updated, this.estimated = false});
  int? remaining;
  int? limit;
  DateTime? resetAt;
  DateTime updated;
  bool estimated;

  Map<String, dynamic> toJson() => {
        'rem': remaining,
        'lim': limit,
        'reset': resetAt?.toIso8601String(),
        'upd': updated.toIso8601String(),
        'est': estimated,
      };

  factory QuotaInfo.fromJson(Map<String, dynamic> j) => QuotaInfo(
        remaining: (j['rem'] as num?)?.toInt(),
        limit: (j['lim'] as num?)?.toInt(),
        resetAt: DateTime.tryParse(j['reset'] ?? ''),
        updated: DateTime.tryParse(j['upd'] ?? '') ?? DateTime.now(),
        estimated: j['est'] == true,
      );
}

class Quota {
  static const aerodatabox = 'aerodatabox';
  static const aviationstack = 'aviationstack';
  static const opensky = 'opensky';

  static QuotaInfo? get(String src) {
    final q = store.quotas[src];
    if (q == null) return null;
    // Past the reset time: the allowance is full again.
    if (q.resetAt != null && DateTime.now().isAfter(q.resetAt!) && q.limit != null) {
      q.remaining = q.limit;
      q.resetAt = _nextReset(src, q.resetAt!);
    }
    return q;
  }

  static DateTime? _nextReset(String src, DateTime last) => switch (src) {
        opensky => last.add(const Duration(days: 1)),
        aviationstack => DateTime(last.year, last.month + 1, 1),
        _ => null,
      };

  /// Reads x-ratelimit-* style headers (RapidAPI, OpenSky).
  static void fromHeaders(String src, Map<String, String> h, {int? status}) {
    int? pick(List<String> keys) {
      for (final k in keys) {
        final v = int.tryParse((h[k] ?? '').trim());
        if (v != null) return v;
      }
      return null;
    }

    var remaining = pick(['x-ratelimit-requests-remaining', 'x-ratelimit-units-remaining', 'x-rate-limit-remaining', 'x-ratelimit-remaining']);
    var limit = pick(['x-ratelimit-requests-limit', 'x-ratelimit-units-limit', 'x-rate-limit-limit', 'x-ratelimit-limit']);
    final resetSec = pick(['x-ratelimit-requests-reset', 'x-ratelimit-units-reset', 'x-rate-limit-retry-after-seconds', 'x-ratelimit-reset']);
    if (status == 429) remaining = 0;
    if (remaining == null && status != 429) return;

    final now = DateTime.now();
    final old = store.quotas[src];
    DateTime? reset = resetSec == null ? null : now.add(Duration(seconds: resetSec));
    if (src == opensky) {
      limit ??= 400; // anonymous daily credits
      final u = now.toUtc();
      reset ??= DateTime.utc(u.year, u.month, u.day + 1).toLocal();
    }
    store.quotas[src] = QuotaInfo(
      remaining: remaining,
      limit: limit ?? old?.limit,
      resetAt: reset ?? old?.resetAt,
      updated: now,
    );
    store.save();
  }

  /// For sources that report nothing: count calls locally against a monthly limit.
  static void count(String src, {required int monthlyLimit}) {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final q = get(src);
    final sameMonth = q != null && q.resetAt != null && q.resetAt!.isAtSameMomentAs(nextMonth);
    store.quotas[src] = QuotaInfo(
      remaining: ((sameMonth ? q.remaining : monthlyLimit) ?? monthlyLimit) - 1,
      limit: monthlyLimit,
      resetAt: nextMonth,
      updated: now,
      estimated: true,
    );
    store.save();
  }
}
