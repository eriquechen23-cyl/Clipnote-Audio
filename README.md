# clipnote_audio

A new Flutter project.

## FFmpeg configuration

This project bundles FFmpeg for both Android and iOS.

### Android
1. Place the FFmpeg shared libraries at `android/ffmpeg-build/<abi>/libffmpeg.so` for
   each supported ABI (`arm64-v8a` and `armeabi-v7a`). Placeholder files are
   provided for development.
2. During the Gradle `preBuild` phase, these libraries are copied into
   `android/app/src/main/jniLibs/<abi>` so they are packaged with the APK.
3. Build the app:

   ```sh
   flutter build apk
   ```

### iOS
1. The `ios/Podfile` includes the `ffmpeg-kit-ios-full` pod which provides
   `FFmpegKit.xcframework`.
2. Install the pods:

   ```sh
   cd ios
   pod install
   ```
3. Open `Runner.xcworkspace` in Xcode and build the project.

These steps ensure that both platforms link against FFmpeg.
