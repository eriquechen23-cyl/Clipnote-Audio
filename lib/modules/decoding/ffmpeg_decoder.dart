import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// Holds decoded PCM data along with metadata like sample rate.
class PcmData {
  final Uint8List buffer;
  final int sampleRate;
  PcmData(this.buffer, this.sampleRate);
}

/// Simple FFmpeg decoder wrapper using `dart:ffi`.
class FFmpegDecoder {
  final DynamicLibrary _lib;
  late final _Decode _decode;
  late final _Free _free;

  FFmpegDecoder({DynamicLibrary? library})
      : _lib = library ?? DynamicLibrary.open('libffmpeg.so') {
    _decode =
        _lib.lookupFunction<_DecodeNative, _Decode>('decode_audio');
    _free = _lib.lookupFunction<_FreeNative, _Free>('free_buffer');
  }

  /// Decode [filePath] into a PCM buffer. The native function returns a
  /// pointer to the PCM data along with its length and sample rate.
  PcmData decode(String filePath) {
    final pathPtr = filePath.toNativeUtf8();
    final lengthPtr = calloc<Int32>();
    final sampleRatePtr = calloc<Int32>();

    final dataPtr = _decode(pathPtr, lengthPtr, sampleRatePtr);
    final length = lengthPtr.value;
    final sampleRate = sampleRatePtr.value;

    final buffer = Uint8List.fromList(dataPtr.asTypedList(length));

    _free(dataPtr);
    calloc.free(pathPtr);
    calloc.free(lengthPtr);
    calloc.free(sampleRatePtr);

    return PcmData(buffer, sampleRate);
  }
}

typedef _DecodeNative = Pointer<Uint8> Function(
    Pointer<Utf8>, Pointer<Int32>, Pointer<Int32>);
typedef _Decode = Pointer<Uint8> Function(
    Pointer<Utf8>, Pointer<Int32>, Pointer<Int32>);

typedef _FreeNative = Void Function(Pointer<Uint8>);
typedef _Free = void Function(Pointer<Uint8>);
