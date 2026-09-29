// The emergency contact, medical condition and allergy dialogs threw a red
// screen when closed — with X or with Save. Each disposed its text controllers
// straight after `await showDialog(...)`, but that future completes when the
// route is popped, not when the dialog is gone. Closing moved focus off the
// field, AppInputField rebuilt during the exit animation, and its TextField
// subscribed to a controller that had already been disposed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/widgets/app_input_field.dart';
import 'package:inaagapay_flutter_v2/widgets/dispose_on_unmount.dart';

/// A page with one button that opens a dialog shaped like the profile ones:
/// an AppInputField and an X that unfocuses and pops.
Future<BuildContext> _pumpPage(WidgetTester tester) async {
  late BuildContext pageContext;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      pageContext = context;
      return const Scaffold();
    }),
  ));
  return pageContext;
}

Widget _dialogBody(TextEditingController ctrl) {
  return Dialog(
    child: Builder(
      builder: (dialogCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              FocusScope.of(dialogCtx).unfocus();
              Navigator.pop(dialogCtx, false);
            },
          ),
          AppInputField(controller: ctrl, hintText: 'First Name'),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets(
      'closing a dialog with a focused field is clean when the controller is '
      'disposed on unmount', (tester) async {
    final pageContext = await _pumpPage(tester);
    final ctrl = TextEditingController();
    var disposed = false;

    final result = showDialog<bool>(
      context: pageContext,
      builder: (_) => DisposeOnUnmount(
        onDispose: () {
          disposed = true;
          ctrl.dispose();
        },
        child: _dialogBody(ctrl),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));

    // The caller reads the fields right after the await; they must still be
    // alive then.
    expect(await result, isFalse);
    expect(ctrl.text, isEmpty);
    expect(disposed, isFalse);

    await tester.pumpAndSettle();

    expect(disposed, isTrue, reason: 'controllers must still be freed');
    expect(tester.takeException(), isNull);
  });
}
