import 'package:hive/hive.dart';

part 'settlement_model.g.dart';

/// A recorded payment that settles part (or all) of a debt within a group.
/// [fromId] paid [toId] [amountCents]. Recorded settlements are subtracted
/// from computed balances so the group can reflect real-world payments.
@HiveType(typeId: 4)
class SettlementModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String groupId;

  @HiveField(2)
  String fromId;

  @HiveField(3)
  String toId;

  /// Amount paid, in minor units (cents/paise).
  @HiveField(4)
  int amountCents;

  @HiveField(5)
  DateTime createdAt;

  SettlementModel({
    required this.id,
    required this.groupId,
    required this.fromId,
    required this.toId,
    required this.amountCents,
    required this.createdAt,
  });
}
