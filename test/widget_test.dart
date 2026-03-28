import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:roomify_mvp/main.dart';

void main() {
  testWidgets('Roomify shows redesigned mobile home after entering app',
      (WidgetTester tester) async {
    await tester.pumpWidget(const RoomifyApp());

    expect(find.text('Vào Roomify'), findsOneWidget);

    await tester.tap(find.text('Vào Roomify'));
    await tester.pumpAndSettle();

    expect(find.text('Tìm nơi phù hợp với bạn'), findsOneWidget);
    expect(find.text('Danh mục'), findsOneWidget);
    expect(find.text('Gợi ý cho bạn'), findsOneWidget);
  });

  testWidgets('Membership payment sheet supports card input formatting',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MembershipPaymentSheet(plan: membershipPlans.first),
        ),
      ),
    );

    await tester.tap(find.text('Thẻ'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '4111 1111 1111 1111'),
      '4111111111111111',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'MM/YY'),
      '1228',
    );

    final editableTexts =
        tester.widgetList<EditableText>(find.byType(EditableText));
    final values =
        editableTexts.map((widget) => widget.controller.text).toList();

    expect(values, contains('4111 1111 1111 1111'));
    expect(values, contains('12/28'));
    expect(find.text('Xác nhận thanh toán bằng thẻ'), findsOneWidget);
  });
}
