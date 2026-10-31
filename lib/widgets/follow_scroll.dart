import 'package:flutter/material.dart';

/// Follow-latest scroll behaviour shared by the process and service detail
/// pages: stick to the bottom while the user is near it, stop as soon as they
/// scroll away, resume when they come back.
///
/// Owns the [ScrollController] so the pages do not each re-implement the
/// threshold, the listener and the post-frame jump.
class FollowLatestController {
  /// Distance from the bottom that still counts as "following".
  static const double threshold = 100.0;

  final ScrollController scrollController = ScrollController();

  bool _following = true;

  /// Starts listening to user scrolls. Call from `initState`.
  void attach() {
    scrollController.addListener(_onScroll);
  }

  /// Stops listening and disposes the controller. Call from `dispose`.
  void detach() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
  }

  /// Content arrived: keep the view pinned when following.
  void onContentChanged() {
    if (!_following) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_following) jumpToBottom();
    });
  }

  /// Clearing the log starts a new session: return to following.
  void reset() {
    _following = true;
  }

  /// Jumps to the newest content immediately.
  void jumpToBottom() {
    if (!scrollController.hasClients) return;
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    _following = (position.maxScrollExtent - position.pixels).abs() < threshold;
  }
}
