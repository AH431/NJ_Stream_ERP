import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../providers/tenant_provider.dart';
import 'onboarding_screen.dart';

/// Dashboard 頂部橫幅：當 [TenantProvider.isOnboarded] 為 false 時顯示。
/// 點擊「立即設定」導向 [OnboardingScreen]。
class OnboardingBanner extends StatelessWidget {
  const OnboardingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final tenant = context.watch<TenantProvider>();

    if (tenant.isOnboarded) return const SizedBox.shrink();

    final s = AppStrings.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary.withAlpha(80),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.rocket_launch_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.onboardBannerTitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                );
                // 完成後重拉狀態讓 Banner 消失
                if (context.mounted) {
                  await context.read<TenantProvider>().fetchTenant(force: true);
                }
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(s.onboardBannerAction),
            ),
          ],
        ),
      ),
    );
  }
}
