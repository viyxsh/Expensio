// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settlement_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SettlementModelAdapter extends TypeAdapter<SettlementModel> {
  @override
  final int typeId = 4;

  @override
  SettlementModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SettlementModel(
      id: fields[0] as String,
      groupId: fields[1] as String,
      fromId: fields[2] as String,
      toId: fields[3] as String,
      amountCents: fields[4] as int,
      createdAt: fields[5] as DateTime,
      status: fields[6] == null ? 'confirmed' : fields[6] as String,
      markedById: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SettlementModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.groupId)
      ..writeByte(2)
      ..write(obj.fromId)
      ..writeByte(3)
      ..write(obj.toId)
      ..writeByte(4)
      ..write(obj.amountCents)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.markedById);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettlementModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
