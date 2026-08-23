import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_shipping_compare/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FR1-FR7 complete Android user flow', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(milliseconds: 150));

    // FR1: the packaged default demo account must work immediately.
    expect(find.text('مقارن الشحن الذكي'), findsOneWidget);
    expect(find.byKey(const Key('demo_account_card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('fill_demo_account')));
    await tester.tap(find.byKey(const Key('auth_submit')));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('new_comparison_button')), findsOneWidget);

    await tester.tap(find.text('الحساب'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();
    final demoLogoutDialog = find.byType(AlertDialog);
    expect(demoLogoutDialog, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: demoLogoutDialog,
        matching: find.widgetWithText(FilledButton, 'تسجيل الخروج'),
      ),
    );
    await tester.pumpAndSettle();

    // FR1: account registration remains available.
    await tester.tap(find.text('حساب جديد'));
    await tester.pumpAndSettle();

    final email =
        'qa${DateTime.now().millisecondsSinceEpoch}@smartshipping.test';
    await tester.enterText(find.byKey(const Key('auth_name')), 'مستخدم اختبار');
    await tester.enterText(find.byKey(const Key('auth_email')), email);
    await tester.enterText(
      find.byKey(const Key('auth_password')),
      'StrongPass123!',
    );
    await tester.tap(find.byKey(const Key('auth_submit')));
    await tester.pumpAndSettle(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('new_comparison_button')), findsOneWidget);

    // FR2 + FR3: enter a valid domestic shipment.
    await tester.tap(find.byKey(const Key('new_comparison_button')));
    await tester.pumpAndSettle();
    expect(find.text('بيانات الشحنة'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('origin_short_address')),
      'RAGI2929',
    );
    await tester.enterText(
      find.byKey(const Key('origin_postal_code')),
      '13337',
    );
    await tester.enterText(
      find.byKey(const Key('destination_short_address')),
      'ABCD1234',
    );
    await tester.enterText(
      find.byKey(const Key('destination_postal_code')),
      '21454',
    );

    final compare = find.byKey(const Key('compare_services_button'));
    await tester.ensureVisible(compare);
    await tester.tap(compare);
    await tester.pump();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 200),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 45),
    );

    // FR4 + FR5: compatible services are retrieved and compared.
    expect(find.byKey(const Key('results_screen')), findsOneWidget);
    expect(find.byKey(const Key('quote_spl_economy')), findsOneWidget);
    expect(find.text('التوصية الذكية'), findsOneWidget);

    // FR6: sorting, filtering, and service details.
    await tester.tap(find.byKey(const Key('sort_price')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter_verified_price')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quote_spl_economy')), findsOneWidget);

    final economyQuote = find.byKey(const Key('quote_spl_economy'));
    await tester.ensureVisible(economyQuote);
    await tester.tap(economyQuote);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('service_detail_screen')), findsOneWidget);
    expect(find.text('تفاصيل الخدمة'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // FR7: save a result and verify recommendation/history persistence.
    final saveButton = find.descendant(
      of: find.byKey(const Key('quote_spl_economy')),
      matching: find.byTooltip('حفظ'),
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.text('تم حفظ الخيار.'), findsOneWidget);

    // Return to the main shell.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('المحفوظة'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saved_screen')), findsOneWidget);
    expect(find.textContaining('SPL'), findsWidgets);

    await tester.tap(find.text('السجل'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history_screen')), findsOneWidget);
    expect(find.textContaining('الرياض'), findsWidgets);

    // Re-run a historical comparison using the current data snapshot.
    final historyItem = find.byKey(
      find
          .byWidgetPredicate(
            (widget) => widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>)
                    .value
                    .startsWith('history_item_'),
          )
          .evaluate()
          .first
          .widget
          .key!,
    );
    await tester.tap(historyItem);
    await tester.pump();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 200),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 45),
    );
    expect(find.byKey(const Key('results_screen')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // FR1 continued: logout then login with the created account.
    await tester.tap(find.text('الحساب'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(FilledButton, 'تسجيل الخروج'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth_email')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('auth_email')), email);
    await tester.enterText(
      find.byKey(const Key('auth_password')),
      'StrongPass123!',
    );
    await tester.tap(find.byKey(const Key('auth_submit')));
    await tester.pumpAndSettle(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('new_comparison_button')), findsOneWidget);
  });
}
