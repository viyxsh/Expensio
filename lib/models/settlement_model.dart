import 'package:hive/hive.dart';

part 'settlement_model.g.dart';

/// A recorded payment that settles part (or all) of a debt within a group.
/// [fromId] paid [toId] [amountCents]. Recorded settlements are subtracted
/// from computed balances so the group can reflect real-world payments.
///
/// Two-sided flow: the payer marks a payment, creating it [statusPending]; the
/// payee (or whoever manages a placeholder payee) confirms it to [statusConfirmed].
@HiveType(typeId: 4)
class SettlementModel extends HiveObject {
  static const statusPending = 'pending';
  static const statusConfirmed = 'confirmed';

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

  /// 'pending' (awaiting the payee's confirmation) or 'confirmed'. Legacy
  /// records (written before two-sided confirmation) default to confirmed.
  @HiveField(6)
  String status;

  /// The user id who marked this payment (drives "awaiting confirmation" vs the
  /// payee's confirm/dispute actions). Null for legacy records.
  @HiveField(7)
  String? markedById;

  SettlementModel({
    required this.id,
    required this.groupId,
    required this.fromId,
    required this.toId,
    required this.amountCents,
    required this.createdAt,
    this.status = statusConfirmed,
    this.markedById,
  });

  bool get isPending => status == statusPending;
  bool get isConfirmed => status == statusConfirmed;
}
