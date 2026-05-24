// ==============================================================================
// onboarding_test.dart — Phase 4 PR-7 M7.2
//
// Widget tests for OnboardingBanner + OnboardingScreen.
//
// Scenarios:
//   1. banner_visible   — OnboardingBanner 顯示，當 isOnboarded = false
//   2. banner_hidden    — OnboardingBanner 不顯示，當 isOnboarded = true
//   3. step_navigation  — 3 步驟 Next/Back 流程正確切換
//   4. finish_calls_patch — 完成時以 markAsOnboarded=true 呼叫 patchTenant
//   5. finish_error     — patchTenant 失敗時顯示 SnackBar 錯誤訊息
// ==============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nj_stream_erp/core/app_strings.dart';
import 'package:nj_stream_erp/providers/tenant_provider.dart';
import 'package:nj_stream_erp/features/onboarding/onboarding_banner.dart';
import 'package:nj_stream_erp/features/onboarding/onboarding_screen.dart';

// ── Helpers ───────────────────────────────────────────────

Dio _noDio() => Dio(BaseOptions(baseUrl: 'http://localhost'));

AppStrings _appStrings() {
  const storage = FlutterSecureStorage();
  return AppStrings(storage);
}

// ── Stub TenantProvider ───────────────────────────────────

class _StubTenantProvider extends TenantProvider {
  _StubTenantProvider({required TenantInfo? stubTenant, this.patchResult = true})
      : super(dio: _noDio()) {
    _stubTenant = stubTenant;
  }

  TenantInfo? _stubTenant;
  bool patchResult;

  // Tracks last patchTenant() call args for assertions
  Map<String, dynamic>? lastPatchArgs;

  @override
  TenantInfo? get tenant => _stubTenant;

  @override
  bool get isOnboarded => _stubTenant?.isOnboarded ?? true;

  @override
  Future<bool> patchTenant({
    String?  name,
    String?  contactEmail,
    String?  timezone,
    bool     markAsOnboarded = false,
  }) async {
    lastPatchArgs = {
      'name':             name,
      'contactEmail':     contactEmail,
      'timezone':         timezone,
      'markAsOnboarded':  markAsOnboarded,
    };
    if (patchResult) {
      _stubTenant = TenantInfo(
        id:          1,
        name:        name ?? _stubTenant?.name ?? '',
        slug:        'test',
        plan:        'basic',
        contactEmail: contactEmail,
        timezone:    timezone ?? 'UTC',
        isActive:    true,
        onboardedAt: markAsOnboarded ? DateTime.now() : null,
      );
      notifyListeners();
    }
    return patchResult;
  }

  @override
  Future<void> fetchTenant({bool force = false}) async {}
}

TenantInfo _notOnboarded() => const TenantInfo(
  id: 1, name: 'Test Co', slug: 'test', plan: 'basic',
  timezone: 'UTC', isActive: true, onboardedAt: null,
);

TenantInfo _onboarded() => TenantInfo(
  id: 1, name: 'Test Co', slug: 'test', plan: 'basic',
  timezone: 'UTC', isActive: true, onboardedAt: DateTime(2026, 1, 1),
);

// ── Pumping helpers ───────────────────────────────────────

Widget _wrapBanner(_StubTenantProvider provider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TenantProvider>.value(value: provider),
      ChangeNotifierProvider<AppStrings>.value(value: _appStrings()),
    ],
    child: const MaterialApp(home: Scaffold(body: OnboardingBanner())),
  );
}

Widget _wrapScreen(_StubTenantProvider provider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TenantProvider>.value(value: provider),
      ChangeNotifierProvider<AppStrings>.value(value: _appStrings()),
    ],
    child: const MaterialApp(home: OnboardingScreen()),
  );
}

// ── Tests ─────────────────────────────────────────────────

void main() {
  group('OnboardingBanner', () {
    testWidgets('1. banner_visible — shown when isOnboarded=false', (tester) async {
      final provider = _StubTenantProvider(stubTenant: _notOnboarded());
      await tester.pumpWidget(_wrapBanner(provider));
      await tester.pump();

      expect(find.byType(OnboardingBanner), findsOneWidget);
      // Container with tertiaryContainer color is rendered (non-empty widget)
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('2. banner_hidden — SizedBox.shrink when isOnboarded=true', (tester) async {
      final provider = _StubTenantProvider(stubTenant: _onboarded());
      await tester.pumpWidget(_wrapBanner(provider));
      await tester.pump();

      // No FilledButton means the banner content is not rendered
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('OnboardingScreen', () {
    testWidgets('3. step_navigation — Next advances step, Back goes back', (tester) async {
      final provider = _StubTenantProvider(stubTenant: _notOnboarded());
      await tester.pumpWidget(_wrapScreen(provider));
      await tester.pump();

      // Step 0: name field visible
      expect(find.byType(TextFormField), findsNWidgets(2));

      // Fill in required name field
      await tester.enterText(
        find.byType(TextFormField).first, 'My Company',
      );
      await tester.pump();

      // Tap Next → step 1
      await tester.tap(find.widgetWithText(FilledButton, '下一步'));
      await tester.pumpAndSettle();

      // Step 1: timezone dropdown visible, no text fields
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

      // Tap Next → step 2
      await tester.tap(find.widgetWithText(FilledButton, '下一步'));
      await tester.pumpAndSettle();

      // Step 2: finish button visible
      expect(find.widgetWithText(FilledButton, '完成設定'), findsOneWidget);

      // Tap Back → back to step 1
      await tester.tap(find.widgetWithText(TextButton, '上一步'));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('4. finish_calls_patch — patchTenant called with markAsOnboarded=true', (tester) async {
      final provider = _StubTenantProvider(stubTenant: _notOnboarded());
      await tester.pumpWidget(_wrapScreen(provider));
      await tester.pump();

      // Step 0: fill name
      await tester.enterText(find.byType(TextFormField).first, 'Acme Corp');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, '下一步'));
      await tester.pumpAndSettle();

      // Step 1: timezone already selected → Next
      await tester.tap(find.widgetWithText(FilledButton, '下一步'));
      await tester.pumpAndSettle();

      // Step 2: finish
      await tester.tap(find.widgetWithText(FilledButton, '完成設定'));
      await tester.pumpAndSettle();

      expect(provider.lastPatchArgs, isNotNull);
      expect(provider.lastPatchArgs!['markAsOnboarded'], isTrue);
      expect(provider.lastPatchArgs!['name'], 'Acme Corp');
    });

    testWidgets('5. finish_error — SnackBar shown when patchTenant fails', (tester) async {
      final provider = _StubTenantProvider(
        stubTenant: _notOnboarded(),
        patchResult: false,
      );
      await tester.pumpWidget(_wrapScreen(provider));
      await tester.pump();

      // Step 0 → 1 → 2
      await tester.enterText(find.byType(TextFormField).first, 'Fail Co');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '下一步'));
      await tester.pumpAndSettle();

      // Tap finish → should show error SnackBar
      await tester.tap(find.widgetWithText(FilledButton, '完成設定'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('儲存失敗，請重試。'), findsOneWidget);
    });
  });
}
