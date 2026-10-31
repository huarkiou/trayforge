import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/log_file_tailer.dart';

void main() {
  late Directory dir;
  late String path;
  late List<String> lines;

  LogFileTailer makeTailer() => LogFileTailer(
    path: path,
    decoder: utf8.decoder,
    onLine: lines.add,
    pollInterval: const Duration(milliseconds: 10),
  );

  void append(String text) {
    File(path).writeAsStringSync(text, mode: FileMode.append, flush: true);
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('trayforge_tailer_test_');
    path = '${dir.path}/app.log';
    lines = [];
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  group('LogFileTailer', () {
    test('ignores content written before start', () {
      append('old line\n');
      final tailer = makeTailer()..start();

      tailer.poll();
      expect(lines, isEmpty, reason: 'start() snapshots the end of file');

      append('new line\n');
      tailer.poll();
      expect(lines, ['new line']);
      tailer.stop();
    });

    test('emits only the appended part of a pre-existing file', () {
      append('old line\n');
      final tailer = makeTailer()..start();

      append('new line\n');
      tailer.poll();
      tailer.stop();

      expect(lines, ['new line']);
    });

    test('waits for the newline before emitting a partial line', () {
      final tailer = makeTailer()..start();

      append('par');
      tailer.poll();
      expect(lines, isEmpty);

      append('tial\n');
      tailer.poll();
      expect(lines, ['partial']);
      tailer.stop();
    });

    test('strips CR from CRLF line endings', () {
      final tailer = makeTailer()..start();

      append('a\r\nb\r\n');
      tailer.poll();
      tailer.stop();

      expect(lines, ['a', 'b']);
    });

    test('preserves empty lines', () {
      final tailer = makeTailer()..start();

      append('a\n\nb\n');
      tailer.poll();
      tailer.stop();

      expect(lines, ['a', '', 'b']);
    });

    test('replays a truncated file from the beginning', () {
      append('first run\n');
      final tailer = makeTailer()..start();

      // Shrinking is the only reliable truncation signal: the tailer cannot
      // tell "rewritten and now longer" from "appended to".
      File(path).writeAsStringSync('ok\n', flush: true);
      tailer.poll();
      tailer.stop();

      expect(lines, ['ok']);
    });

    test('flushes a trailing line without newline on stop', () {
      final tailer = makeTailer()..start();

      append('no trailing newline');
      tailer.poll();
      expect(lines, isEmpty);

      tailer.stop();
      expect(lines, ['no trailing newline']);
    });

    test('picks up a file created after start', () {
      final tailer = makeTailer()..start();

      tailer.poll();
      expect(lines, isEmpty);

      File(path).writeAsStringSync('created later\n', flush: true);
      tailer.poll();
      tailer.stop();

      expect(lines, ['created later']);
    });

    test('polls on its own timer and stops when stopped', () async {
      final tailer = makeTailer()..start();
      append('from the timer\n');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(lines, ['from the timer']);

      tailer.stop();
      append('after stop\n');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(lines, ['from the timer']);
    });

    test('start is idempotent and stop is safe before start', () {
      final tailer = makeTailer();

      expect(tailer.stop, returnsNormally);
      tailer.start();
      tailer.start();
      append('once\n');
      tailer.poll();
      tailer.stop();

      expect(lines, ['once']);
    });
  });
}
