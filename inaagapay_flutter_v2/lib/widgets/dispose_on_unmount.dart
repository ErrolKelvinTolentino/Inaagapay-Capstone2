// lib/widgets/dispose_on_unmount.dart

import 'package:flutter/widgets.dart';

/// Runs [onDispose] when this subtree leaves the widget tree.
///
/// The point is timing. A dialog's or sheet's future completes when the route
/// is popped, not when it is gone — its text fields keep rebuilding through the
/// exit animation. Closing the keyboard on the way out changes the MediaQuery,
/// the dialog rebuilds, and each TextField subscribes to its controller again.
/// A controller disposed straight after `await showDialog(...)` is already
/// dead by then, and a debug build turns that into a red error screen.
///
/// Anything the fields still point at has to outlive the route, and the
/// framework already knows exactly when the tree is torn down, so the cleanup
/// is hung off a State's dispose rather than guessed at with a delay. Values
/// read from the controllers straight after the `await` are still safe: the
/// route is only unmounted once its exit animation has finished.
class DisposeOnUnmount extends StatefulWidget {
  const DisposeOnUnmount({
    super.key,
    required this.onDispose,
    required this.child,
  });

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<DisposeOnUnmount> createState() => _DisposeOnUnmountState();
}

class _DisposeOnUnmountState extends State<DisposeOnUnmount> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
