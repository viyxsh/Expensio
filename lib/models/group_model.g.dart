// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GroupModelAdapter extends TypeAdapter<GroupModel> {
  @override
  final int typeId = 3;

  @override
  GroupModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final numFields = numOfFields;
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return GroupModel(
      id: fields[0] as String,
      name: fields[1] as String,
      memberIds: (fields[2] as List).cast<String>(),
      createdAt: fields[3] as DateTime,
      description: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, GroupModel obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.memberIds)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.description);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is GroupModelAdapter &&
              runtimeType == other.runtimeType &&
              typeId == other.typeId;
}