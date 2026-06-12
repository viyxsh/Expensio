// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExpenseModelAdapter extends TypeAdapter<ExpenseModel> {
  @override
  final int typeId = 2;

  @override
  ExpenseModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExpenseModel(
      id: fields[0] as String,
      title: fields[1] as String,
      totalAmount: fields[2] as int,
      payerId: fields[3] as String,
      participantIds: (fields[4] as List).cast<String>(),
      groupId: fields[5] as String,
      createdAt: fields[6] as DateTime,
      items: (fields[7] as List).cast<BillItem>(),
      category: fields[8] as String,
      isPersonal: fields[9] as bool,
      splitMap: (fields[10] as Map).cast<String, int>(),
    );
  }

  @override
  void write(BinaryWriter writer, ExpenseModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.totalAmount)
      ..writeByte(3)
      ..write(obj.payerId)
      ..writeByte(4)
      ..write(obj.participantIds)
      ..writeByte(5)
      ..write(obj.groupId)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.items)
      ..writeByte(8)
      ..write(obj.category)
      ..writeByte(9)
      ..write(obj.isPersonal)
      ..writeByte(10)
      ..write(obj.splitMap);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ExpenseModelAdapter &&
              runtimeType == other.runtimeType &&
              typeId == other.typeId;
}