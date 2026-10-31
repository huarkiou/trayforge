import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/l10n/validation_text.dart';

import '../helpers/localized_app.dart';

void main() {
  final cases = <String, UnitValidationError>{
    'empty process name': UnitValidationError.emptyName(UnitKind.process),
    'empty service-group name': UnitValidationError.emptyName(UnitKind.service),
    'name with a separator': UnitValidationError.nameSeparator(
      UnitKind.process,
      'a/b',
    ),
    'service group without services': UnitValidationError.noServices('g'),
    'invalid webui_pattern': UnitValidationError.invalidWebuiPattern(
      'unterminated group',
    ),
  };

  group('UnitValidationError', () {
    for (final entry in cases.entries) {
      test('${entry.key}: the English message matches the ARB text', () {
        // The English `ArgumentError.message` is a hand-written fallback; the
        // ARB text is the real copy. This pins the two together, so editing one
        // without the other fails here instead of drifting silently.
        final error = entry.value;
        expect(error.message, error.describe(enStrings));
      });
    }

    test('carries the payload the formatter needs', () {
      expect(
        UnitValidationError.emptyName(UnitKind.service).unitKind,
        UnitKind.service,
      );
      expect(
        UnitValidationError.nameSeparator(UnitKind.process, 'a/b').unitName,
        'a/b',
      );
      expect(UnitValidationError.noServices('g').unitName, 'g');
      expect(UnitValidationError.invalidWebuiPattern('x').detail, 'x');
    });

    test('renders the reason and its payload in Chinese', () {
      expect(
        UnitValidationError.emptyName(UnitKind.service).describe(zhStrings),
        '服务组名称不能为空',
      );
      expect(
        UnitValidationError.nameSeparator(
          UnitKind.process,
          'a/b',
        ).describe(zhStrings),
        r'进程名称“a/b”不能包含 / 或 \',
      );
      expect(
        UnitValidationError.noServices('g').describe(zhStrings),
        '服务组“g”至少需要一个服务',
      );
      expect(
        UnitValidationError.invalidWebuiPattern(
          'unterminated',
        ).describe(zhStrings),
        '无效的 webui_pattern 正则表达式：unterminated',
      );
    });

    test('is still an ArgumentError', () {
      expect(UnitValidationError.noServices('g'), isA<ArgumentError>());
    });
  });
}
