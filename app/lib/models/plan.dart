class Plan {
  Plan({
    required this.id,
    required this.name,
    required this.priceUsd,
    required this.currency,
    this.exportLimit,
    required this.quality,
    required this.maxDevices,
    required this.features,
  });

  final String id;
  final String name;
  final double priceUsd;
  final String currency;
  final int? exportLimit; // null = unlimited
  final String quality;
  final int maxDevices;
  final List<String> features;

  String get exportLabel => exportLimit == null ? 'Unlimited exports' : '$exportLimit exports / mo';

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
        id: j['id'] as String,
        name: j['name'] as String,
        priceUsd: (j['price_usd'] as num).toDouble(),
        currency: (j['currency'] ?? 'USDT') as String,
        exportLimit: j['export_limit'] as int?,
        quality: (j['quality'] ?? '1080p') as String,
        maxDevices: (j['max_devices'] ?? 2) as int,
        features: ((j['features'] ?? []) as List).map((e) => e.toString()).toList(),
      );
}
