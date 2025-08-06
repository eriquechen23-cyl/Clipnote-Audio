import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'native_library.dart';

/// FFI wrapper around a platform specific PCM audio player.
class PcmPlayer {
  final DynamicLibrary _lib;
  late final _Create _create;
  late final _Dispose _dispose;
  late final _Load _load;
  late final _Play _play;
  late final _Pause _pause;
  late final _Position _position;

  late final int _handle;
  bool _playing = false;

  PcmPlayer({DynamicLibrary? library})
      : _lib = library ?? loadNativeLibrary('audioplayer') {
    _create = _lib.lookupFunction<_CreateNative, _Create>('player_create');
    _dispose = _lib.lookupFunction<_DisposeNative, _Dispose>('player_dispose');
    _load = _lib.lookupFunction<_LoadNative, _Load>('player_load');
    _play = _lib.lookupFunction<_PlayNative, _Play>('player_play');
    _pause = _lib.lookupFunction<_PauseNative, _Pause>('player_pause');
    _position =
        _lib.lookupFunction<_PositionNative, _Position>('player_position');
    _handle = _create();
  }

  Future<void> load(Uint8List pcm, int sampleRate) async {
    final ptr = calloc<Uint8>(pcm.length);
    ptr.asTypedList(pcm.length).setAll(0, pcm);
    _load(_handle, ptr, pcm.length, sampleRate);
    calloc.free(ptr);
  }

  Future<void> play() async {
    _play(_handle);
    _playing = true;
  }

  Future<void> pause() async {
    _pause(_handle);
    _playing = false;
  }

  Duration get position => Duration(milliseconds: _position(_handle));
  bool get playing => _playing;

  Future<void> dispose() async {
    _dispose(_handle);
  }
}

typedef _CreateNative = Int32 Function();
typedef _Create = int Function();

typedef _DisposeNative = Void Function(Int32);
typedef _Dispose = void Function(int);

typedef _LoadNative = Void Function(
    Int32, Pointer<Uint8>, Int32, Int32);
typedef _Load = void Function(int, Pointer<Uint8>, int, int);

typedef _PlayNative = Void Function(Int32);
typedef _Play = void Function(int);

typedef _PauseNative = Void Function(Int32);
typedef _Pause = void Function(int);

typedef _PositionNative = Int64 Function(Int32);
typedef _Position = int Function(int);
