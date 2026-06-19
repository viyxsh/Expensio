import 'package:hive/hive.dart';
import 'bill_item_model.dart';

part 'expense_model.g.dart';

@HiveType(typeId: 2)
class ExpenseModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  /// Total amount in minor units (cents/paise).
  @HiveField(2)
  int totalAmount;

  @HiveField(3)
  String payerId;

  @HiveField(4)
  List<String> participantIds;

  @HiveField(5)
  String groupId;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  List<BillItem> items;

  @HiveField(8)
  String category;

  @HiveField(9)
  bool isPersonal;

  // Split map: userId to amount they owe, in minor units (cents/paise)
  @HiveField(10)
  Map<String, int> splitMap;

  /// User id who created this expense. Drives who may edit/delete it. Empty for
  /// legacy expenses (callers fall back to [payerId]).
  @HiveField(11, defaultValue: '')
  String createdBy;

  ExpenseModel({
    required this.id,
    required this.title,
    required this.totalAmount,
    required this.payerId,
    required this.participantIds,
    required this.groupId,
    required this.createdAt,
    List<BillItem>? items,
    this.category = 'General',
    this.isPersonal = false,
    Map<String, int>? splitMap,
    this.createdBy = '',
  })  : items = items ?? [],
        splitMap = splitMap ?? {};

  /// The id that controls edit/delete rights (creator, or payer for legacy).
  String get ownerId => createdBy.isNotEmpty ? createdBy : payerId;
}