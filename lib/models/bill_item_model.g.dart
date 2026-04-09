// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bill_item_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BillItemAdapter extends TypeAdapter<BillItem> {
  @override
  final int typeId = 1;

  @override
  BillItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BillItem(
      name: fields[0] as String,
      price: fields[1] as double,
      category: fields[2] as String,
      quantity: fields[3] as int,
      assignedUserIds: (fields[4] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, BillItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.price)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.quantity)
      ..writeByte(4)
      ..write(obj.assignedUserIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is BillItemAdapter &&
              runtimeType == other.runtimeType &&
              typeId == other.typeId;
}