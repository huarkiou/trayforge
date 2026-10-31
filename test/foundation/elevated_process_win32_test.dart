import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/elevated_process_win32.dart';

void main() {
  group('quoteWindowsArgument', () {
    test('leaves plain arguments untouched', () {
      expect(quoteWindowsArgument('--fast'), '--fast');
      expect(quoteWindowsArgument(r'D:\Apps\x.exe'), r'D:\Apps\x.exe');
    });

    test('quotes arguments containing spaces or tabs', () {
      expect(quoteWindowsArgument('a b'), '"a b"');
      expect(quoteWindowsArgument('a\tb'), '"a\tb"');
      expect(
        quoteWindowsArgument('-File license svcs.ps1'),
        '"-File license svcs.ps1"',
      );
    });

    test('quotes the empty argument', () {
      expect(quoteWindowsArgument(''), '""');
    });

    test('escapes embedded quotes and the backslashes before them', () {
      expect(quoteWindowsArgument(r'a"b'), r'"a\"b"');
      expect(
        quoteWindowsArgument(r'C:\dir with space\"quote'),
        r'"C:\dir with space\\\"quote"',
      );
    });

    test('doubles a trailing backslash inside a quoted argument', () {
      expect(
        quoteWindowsArgument(r'C:\dir with space\'),
        r'"C:\dir with space\\"',
      );
    });
  });
}
