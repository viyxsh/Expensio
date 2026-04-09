import 'package:hive/hive.dart';

part 'bill_item_model.g.dart';

@HiveType(typeId: 1)
class BillItem extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  double price;

  @HiveField(2)
  String category;

  @HiveField(3)
  int quantity;

  // Assigned user IDs (for item-level splitting)
  @HiveField(4)
  List<String> assignedUserIds;

  BillItem({
    required this.name,
    required this.price,
    required this.category,
    this.quantity = 1,
    List<String>? assignedUserIds,
  }) : assignedUserIds = assignedUserIds ?? [];

  double get totalPrice => price * quantity;

  factory BillItem.fromJson(Map<String, dynamic> json) {
    return BillItem(
      name: json['name']?.toString() ?? 'Unknown Item',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      category: json['category']?.toString() ?? 'General',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
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