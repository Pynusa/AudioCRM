import 'dart:convert';
import 'dart:typed_data';

/// Minimal protobuf (proto3) encoder/decoder — enough for the NVIDIA Riva ASR
/// messages, so no protoc code generation is required.
class ProtoWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void _varint(int v) {
    var value = v;
    if (value < 0) {
      // proto3 int32 negative → 10-byte two's complement varint
      value = value & 0xFFFFFFFFFFFFFFFF;
    }
    while (true) {
      if ((value & ~0x7F) == 0) {
        _b.addByte(value);
        return;
      }
      _b.addByte((value & 0x7F) | 0x80);
      value = value >>> 7;
    }
  }

  void _tag(int field, int wire) => _varint((field << 3) | wire);

  void int32(int field, int v) {
    if (v == 0) return;
    _tag(field, 0);
    _varint(v);
  }

  void boolean(int field, bool v) {
    if (!v) return;
    _tag(field, 0);
    _varint(1);
  }

  void bytes(int field, List<int> v) {
    _tag(field, 2);
    _varint(v.length);
    _b.add(v);
  }

  void string(int field, String v) {
    if (v.isEmpty) return;
    bytes(field, utf8.encode(v));
  }

  void message(int field, ProtoWriter m) => bytes(field, m.toBytes());

  Uint8List toBytes() => _b.toBytes();
}

class ProtoField {
  final int number;
  final int wire;
  final int? varint;
  final Uint8List? bytes;
  final int? fixed32;
  ProtoField(this.number, this.wire, {this.varint, this.bytes, this.fixed32});

  String get asString => utf8.decode(bytes ?? Uint8List(0), allowMalformed: true);

  int get asInt32 {
    final v = varint ?? 0;
    return v.toSigned(32);
  }

  double get asFloat {
    final bd = ByteData(4)..setUint32(0, fixed32 ?? 0, Endian.little);
    return bd.getFloat32(0, Endian.little);
  }
}

List<ProtoField> protoDecode(List<int> data) {
  final buf = data is Uint8List ? data : Uint8List.fromList(data);
  final out = <ProtoField>[];
  var i = 0;
  int readVarint() {
    var result = 0;
    var shift = 0;
    while (i < buf.length) {
      final b = buf[i++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  while (i < buf.length) {
    final key = readVarint();
    final field = key >> 3;
    final wire = key & 7;
    switch (wire) {
      case 0:
        out.add(ProtoField(field, wire, varint: readVarint()));
        break;
      case 1:
        i += 8;
        break;
      case 2:
        final len = readVarint();
        final end = (i + len).clamp(0, buf.length);
        out.add(ProtoField(field, wire, bytes: Uint8List.sublistView(buf, i, end)));
        i = end;
        break;
      case 5:
        final bd = ByteData.sublistView(buf, i, i + 4);
        out.add(ProtoField(field, wire, fixed32: bd.getUint32(0, Endian.little)));
        i += 4;
        break;
      default:
        return out; // unknown wire type → stop parsing
    }
  }
  return out;
}
