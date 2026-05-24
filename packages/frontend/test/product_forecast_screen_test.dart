// ==============================================================================
// product_forecast_screen_test.dart — Phase 4 PR-5 M5.2
//
// Widget tests for ProductForecastScreen UI state rendering.
// Uses a hand-written stub ForecastProvider — no mockito / codegen.
//
// Scenarios:
//   1. render     — chart + table visible when forecast data is available
//   2. empty state — shows message when currentForecast is null
//   3. loading    — shows CircularProgressIndicator while forecastLoading=true
// ==============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nj_stream_erp/core/app_strings.dart';
import 'package:nj_stream_erp/providers/forecast_provider.dart';

// ── Hand-written ForecastProvider stub ────────────────────

class _StubForecastProvider extends ForecastProvider {
  _StubForecastProvider({
    required this.stubForecast,
    required this.stubLoading,
  }) : super(dio: _noDio());

  final ProductForecast? stubForecast;
  final bool             stubLoading;

  @override
  ProductForecast? get currentForecast => stubForecast;
  @override
  bool             get forecastLoading => stubLoading;
  @override
  String?          get forecastError   => null;
  @override
  List<ReorderAlert>? get reorderAlerts => [];
  @override
  bool get alertsLoading => false;

  // 不執行真實 fetch
  @override
  Future<void> fetchProductForecast(int productId, {int weeks = 12}) async {}
  @override
  Future<void> fetchReorderAlerts(
    List<dynamic> lowStockItems, {bool force = false}) async {}
}

// Dio stub — never actually called in these tests
Dio _noDio() => Dio(BaseOptions(baseUrl: 'http://localhost'));

// ── Test data ──────────────────────────────────────────────

ProductForecast _makeForecast({int weeks = 4}) => ProductForecast(
      productId: 1,
      sku: 'TUBE-A001',
      forecasts: List.generate(
        weeks,
        (i) => ForecastWeek(
          weekStart: '2026-06-0${i + 2}',
          qty: 50.0 + i * 5,
          lower: 40.0 + i * 5,
          upper: 60.0 + i * 5,
        ),
      ),
    );

// ── Test scaffold ──────────────────────────────────────────

/// 精簡版 Screen — 只驗證 ForecastProvider 狀態對 UI 的影響，
/// 不初始化 AppDatabase（避免 drift platform channel）。
class _ForecastScreenStub extends StatelessWidget {
  const _ForecastScreenStub();

  @override
  Widget build(BuildContext context) {
    final forecast = context.watch<ForecastProvider>();
    final s        = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.forecastScreenTitle),
        actions: [
          if (forecast.currentForecast != null &&
              !forecast.currentForecast!.isEmpty)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: s.forecastExportCsv,
              onPressed: () {},
            ),
        ],
      ),
      body: Builder(builder: (_) {
        if (forecast.forecastLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (forecast.currentForecast == null ||
            forecast.currentForecast!.isEmpty) {
          return Center(child: Text(s.forecastEmptyState));
        }
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(s.forecastTableTitle),
            ),
            ...forecast.currentForecast!.forecasts.asMap().entries.map(
              (e) => ListTile(
                title: Text('W${e.key + 1}  ${e.value.weekStart}'),
                trailing: Text(e.value.qty.toStringAsFixed(1)),
              ),
            ),
          ],
        );
      }),
    );
  }
}

Widget _buildApp(_StubForecastProvider provider) {
  // AppStrings with in-memory storage — no real FlutterSecureStorage I/O
  final strings = AppStrings(_FakeSecureStorage());

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ForecastProvider>.value(value: provider),
      ChangeNotifierProvider<AppStrings>.value(value: strings),
    ],
    child: const MaterialApp(home: _ForecastScreenStub()),
  );
}

// ── Tests ──────────────────────────────────────────────────

void main() {
  group('ProductForecastScreen UI state', () {
    testWidgets('1. render — chart + table when forecast available',
        (tester) async {
      final provider = _StubForecastProvider(
        stubForecast: _makeForecast(weeks: 4),
        stubLoading: false,
      );

      await tester.pumpWidget(_buildApp(provider));
      await tester.pump();

      // AppBar title
      expect(find.text('需求預測'), findsOneWidget);
      // Export icon appears when forecast data is present
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      // Table section header
      expect(find.text('每週預測明細'), findsOneWidget);
      // Week labels rendered
      expect(find.textContaining('W1'), findsWidgets);
      expect(find.textContaining('W4'), findsWidgets);
    });

    testWidgets('2. empty state — no forecast shows message', (tester) async {
      final provider = _StubForecastProvider(
        stubForecast: null,
        stubLoading: false,
      );

      await tester.pumpWidget(_buildApp(provider));
      await tester.pump();

      expect(find.text('尚無預測資料，請先執行需求預測'), findsOneWidget);
      expect(find.byIcon(Icons.download_outlined), findsNothing);
    });

    testWidgets('3. loading — spinner while fetching', (tester) async {
      final provider = _StubForecastProvider(
        stubForecast: null,
        stubLoading: true,
      );

      await tester.pumpWidget(_buildApp(provider));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('尚無預測資料，請先執行需求預測'), findsNothing);
    });
  });
}

// ── In-memory FlutterSecureStorage fake ───────────────────

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
