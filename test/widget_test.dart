import 'package:clipnote_audio/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders MultiTrackEditor', (tester) async {
    await tester.pumpWidget(const ClipNoteAudioApp());
    expect(find.text('多軌編輯器'), findsOneWidget);
  });
}
