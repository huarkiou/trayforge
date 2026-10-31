/// Tails a log file and emits the lines appended to it.
///
/// Needed because an elevated process (UAC broker) cannot inherit TrayForge's
/// stdout/stderr pipes: the only output channel left is a file the process
/// writes itself. A tailer also serves ordinary processes that already log to
/// a file instead of stdout.
///
/// Semantics, chosen to match a supervised process starting once:
///
/// - [start] snapshots the current end of file; **only lines appended after
///   that point** are emitted. Restarting a long-running daemon therefore does
///   not replay its whole backlog.
/// - A file that shrinks (truncated/recreated by the process) is replayed from
///   the beginning — that is a fresh log, not a continuation.
/// - Incomplete trailing lines are held back until their newline arrives, so a
///   line is never split across emissions. [stop] flushes the remainder.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LogFileTailer {
  LogFileTailer({
    required this.path,
    required this.decoder,
    required this.onLine,
    this.pollInterval = const Duration(milliseconds: 300),
  });

  /// Absolute path of the file to tail.
  final String path;

  /// Called with each complete line appended to [path].
  final void Function(String line) onLine;

  /// How often [poll] runs while a process is alive.
  final Duration pollInterval;

  /// Decodes appended bytes into text (lenient decoders preferred).
  final Converter<List<int>, String> decoder;

  Timer? _timer;

  /// Bytes already emitted, as an absolute file offset.
  int _offset = 0;

  /// Text after the last newline, waiting for the rest of its line.
  String _carry = '';

  bool _running = false;

  /// Snapshots the current end of file and starts polling.
  ///
  /// Call **before** launching the process so nothing it writes is missed.
  /// Idempotent while running.
  void start() {
    if (_running) return;
    _running = true;
    _offset = _length() ?? 0;
    _timer = Timer.periodic(pollInterval, (_) => poll());
  }

  /// Emits everything appended since the last poll, then stops polling.
  ///
  /// Flushes a trailing partial line (a process may exit right after writing
  /// its last line without a newline). Idempotent.
  void stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    poll();
    if (_carry.isNotEmpty) {
      final line = _carry;
      _carry = '';
      onLine(line);
    }
  }

  /// Reads and emits everything appended since the previous poll.
  ///
  /// Public so tests can drive it without timers.
  void poll() {
    final length = _length();
    if (length == null) return;

    if (length < _offset) {
      // Truncated or recreated: replay the new content from the start.
      _offset = 0;
      _carry = '';
    }
    if (length <= _offset) return;

    final chunk = _read(_offset, length - _offset);
    if (chunk == null || chunk.isEmpty) return;
    _offset += chunk.length;

    final text = '$_carry${decoder.convert(chunk)}';
    final parts = text.split('\n');
    _carry = parts.removeLast();
    for (final raw in parts) {
      onLine(raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw);
    }
  }

  // ---------------------------------------------------------------------------
  // File access
  // ---------------------------------------------------------------------------

  /// Current file length, or `null` when the file is missing or unreadable.
  int? _length() {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return file.lengthSync();
    } catch (_) {
      return null;
    }
  }

  /// Reads [count] bytes at [offset], or `null` when the read fails.
  ///
  /// A writer that keeps the file open may briefly deny the read; the next
  /// poll simply retries.
  List<int>? _read(int offset, int count) {
    RandomAccessFile? handle;
    try {
      handle = File(path).openSync(mode: FileMode.read);
      handle.setPositionSync(offset);
      return handle.readSync(count);
    } catch (_) {
      return null;
    } finally {
      try {
        handle?.closeSync();
      } catch (_) {
        // Already closed or failed to close — nothing to do.
      }
    }
  }
}
