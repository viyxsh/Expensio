import 'package:hive/hive.dart';

part 'bill_item_model.g.dart';

@HiveType(typeId: 1)
class BillItem extends HiveObject {
  @HiveField(0)
  String name;

  /// Unit price as printed on the document. Null when the value is not
  /// explicitly visible or cannot be reliably determined — never defaulted
  /// to zero or inferred.
  @HiveField(1)
  double? price;

  @HiveField(2)
  String category;

  /// Quantity as printed on the document. Null when not explicitly shown;
  /// line math treats a missing quantity as a single unit.
  @HiveField(3)
  int? quantity;

  // Assigned user IDs (for item-level splitting)
  @HiveField(4)
  List<String> assignedUserIds;

  BillItem({
    required this.name,
    this.price,
    required this.category,
    this.quantity,
    List<String>? assignedUserIds,
  }) : assignedUserIds = assignedUserIds ?? [];

  /// Line total, or null when the price is unknown.
  double? get totalPrice =>
      price == null ? null : price! * (quantity ?? 1);

  bool get hasPrice => price != null;

  factory BillItem.fromJson(Map<String, dynamic> json) {
    return BillItem(
      name: json['name']?.toString() ?? 'Unknown Item',
      // Absent / illegible values stay null — no zero fallback.
      price: (json['price'] as num?)?.toDouble(),
      category: json['category']?.toString() ?? 'General',
      quantity: (json['quantity'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'category': category,
    'quantity': quantity,
  };

  BillItem copyWith({
    String? name,
    double? price,
    String? category,
    int? quantity,
    List<String>? assignedUserIds,
  }) {
    return BillItem(
      name: name ?? this.name,
      price: price ?? this.price,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      assignedUserIds: assignedUserIds ?? List.from(this.assignedUserIds),
    );
  }
}
