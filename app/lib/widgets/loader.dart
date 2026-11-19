import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import 'common.dart';

/// Loads data once (and again whenever [reloadToken] changes), showing a
/// spinner, an error with "Try again", or the content.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.reloadToken, this.frame});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Object? reloadToken;

  /// Optional wrapper (e.g. a Scaffold with an app bar) for the loading and
  /// error states, for pages whose content brings its own Scaffold.
  final Widget Function(Widget child)? frame;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  void didUpdateWidget(covariant Loader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      _future = widget.load();
    }
  }

  Future<void> _reload() async {
    final next = widget.load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The error is shown by the FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        final done = snapshot.connectionState == ConnectionState.done;
        final Widget Function(Widget) frame = widget.frame ?? ((Widget child) => child);
        if (done && snapshot.hasError) {
          return frame(ErrorView(message: errorText(snapshot.error!), onRetry: _reload));
        }
        if (snapshot.hasData) {
          // While reloading, keep showing the previous data.
          return widget.builder(context, snapshot.data as T, _reload);
        }
        return frame(const LoadingView());
      },
    );
  }
}
