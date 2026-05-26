import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../providers/tenant_provider.dart';

/// 3-step onboarding stepper
///   Step 0: 公司基本資料（name + contactEmail）
///   Step 1: 時區設定
///   Step 2: 完成確認
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  // Step 0 form
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;

  // Step 1 timezone
  String _timezone = 'UTC';

  bool _saving = false;

  static const _timezones = [
    'UTC',
    'Asia/Taipei',
    'Asia/Tokyo',
    'Asia/Shanghai',
    'Asia/Singapore',
    'Asia/Seoul',
    'Asia/Hong_Kong',
    'America/New_York',
    'America/Chicago',
    'America/Los_Angeles',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'Australia/Sydney',
  ];

  @override
  void initState() {
    super.initState();
    final tenant = context.read<TenantProvider>().tenant;
    _nameCtrl  = TextEditingController(text: tenant?.name  ?? '');
    _emailCtrl = TextEditingController(text: tenant?.contactEmail ?? '');
    _timezone  = tenant?.timezone ?? 'UTC';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_step == 0 && !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _step++);
  }

  void _goBack() => setState(() => _step--);

  Future<void> _finish() async {
    final s      = AppStrings.read(context);
    final tenant = context.read<TenantProvider>();

    setState(() => _saving = true);
    final ok = await tenant.patchTenant(
      name:            _nameCtrl.text.trim(),
      contactEmail:    _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      timezone:        _timezone,
      markAsOnboarded: true,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.onboardErrSave)),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.onboardScreenTitle)),
      body: SafeArea(
        child: Stepper(
          currentStep: _step,
          onStepContinue: _step < 2 ? _goNext : (_saving ? null : _finish),
          onStepCancel:   _step > 0 ? _goBack : null,
          controlsBuilder: (context, details) {
            // 只渲染當前 active step 的控制列，避免測試 finder 找到多個相同按鈕
            if (details.stepIndex != details.currentStep) {
              return const SizedBox.shrink();
            }
            return _StepperControls(details: details, step: _step, saving: _saving);
          },
          steps: [
            Step(
              title: Text(s.onboardStep1Title),
              isActive: _step >= 0,
              state: _step > 0 ? StepState.complete : StepState.indexed,
              content: _Step0Form(
                formKey:   _formKey,
                nameCtrl:  _nameCtrl,
                emailCtrl: _emailCtrl,
              ),
            ),
            Step(
              title: Text(s.onboardStep2Title),
              isActive: _step >= 1,
              state: _step > 1 ? StepState.complete : StepState.indexed,
              content: _Step1Timezone(
                selected: _timezone,
                timezones: _timezones,
                onChanged: (v) => setState(() => _timezone = v),
              ),
            ),
            Step(
              title: Text(s.onboardStep3Title),
              isActive: _step >= 2,
              state: StepState.indexed,
              content: _Step2Done(
                name:     _nameCtrl.text,
                email:    _emailCtrl.text,
                timezone: _timezone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step controls ─────────────────────────────────────────

class _StepperControls extends StatelessWidget {
  final ControlsDetails details;
  final int  step;
  final bool saving;

  const _StepperControls({
    required this.details,
    required this.step,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          FilledButton(
            onPressed: saving ? null : details.onStepContinue,
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            child: saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(step < 2 ? s.onboardBtnNext : s.onboardBtnFinish),
          ),
          if (step > 0) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: details.onStepCancel,
              child: Text(s.onboardBtnBack),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Step 0：公司資料 ──────────────────────────────────────

class _Step0Form extends StatelessWidget {
  final GlobalKey<FormState>   formKey;
  final TextEditingController  nameCtrl;
  final TextEditingController  emailCtrl;

  const _Step0Form({
    required this.formKey,
    required this.nameCtrl,
    required this.emailCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          TextFormField(
            controller: nameCtrl,
            decoration: InputDecoration(labelText: s.onboardFieldName),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? s.onboardErrName : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: emailCtrl,
            decoration: InputDecoration(labelText: s.onboardFieldEmail),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final re = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
              return re.hasMatch(v.trim()) ? null : s.onboardErrEmail;
            },
          ),
        ],
      ),
    );
  }
}

// ── Step 1：時區 ──────────────────────────────────────────

class _Step1Timezone extends StatelessWidget {
  final String          selected;
  final List<String>    timezones;
  final ValueChanged<String> onChanged;

  const _Step1Timezone({
    required this.selected,
    required this.timezones,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownButtonFormField<String>(
      // Flutter SDK compatibility: older channels only expose `value`,
      // while newer analyzers mark it deprecated in favor of `initialValue`.
      // ignore: deprecated_member_use
      value: selected,
      decoration: InputDecoration(labelText: s.onboardFieldTz),
      items: timezones.map((tz) => DropdownMenuItem(
        value: tz,
        child: Text(tz, style: const TextStyle(fontSize: 14)),
      )).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }
}

// ── Step 2：完成摘要 ──────────────────────────────────────

class _Step2Done extends StatelessWidget {
  final String name;
  final String email;
  final String timezone;

  const _Step2Done({
    required this.name,
    required this.email,
    required this.timezone,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.onboardStep3Body,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SummaryRow(label: s.onboardFieldName.replaceAll(' *', ''), value: name),
        if (email.trim().isNotEmpty)
          _SummaryRow(label: s.onboardFieldEmail, value: email),
        _SummaryRow(label: s.onboardFieldTz, value: timezone),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
