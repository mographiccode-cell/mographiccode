import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool registerMode = false;
  bool obscurePassword = true;
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.primaryContainer.withValues(alpha: .75),
              const Color(0xFFF7F9FA),
              const Color(0xFFF7F9FA),
            ],
            stops: const [0, .38, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: .18),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.local_shipping_rounded,
                        size: 44,
                        color: cs.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'مقارن الشحن الذكي',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF183236),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'قارن خدمات الشحن المحلية والدولية ببيانات موثقة وتوصية قابلة للتفسير.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF5F7175),
                            height: 1.5,
                          ),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SegmentedButton<bool>(
                                key: const Key('auth_mode_switch'),
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    label: Text('تسجيل الدخول'),
                                    icon: Icon(Icons.login_rounded),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: Text('حساب جديد'),
                                    icon: Icon(Icons.person_add_alt_1),
                                  ),
                                ],
                                selected: {registerMode},
                                onSelectionChanged: controller.busy
                                    ? null
                                    : (s) => setState(
                                          () => registerMode = s.first,
                                        ),
                              ),
                              const SizedBox(height: 18),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: registerMode
                                    ? Padding(
                                        key: const ValueKey('register-name'),
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: TextFormField(
                                          key: const Key('auth_name'),
                                          controller: name,
                                          textInputAction: TextInputAction.next,
                                          autofillHints: const [AutofillHints.name],
                                          decoration: const InputDecoration(
                                            labelText: 'الاسم الكامل',
                                            prefixIcon: Icon(Icons.person_outline),
                                          ),
                                          validator: (v) =>
                                              (v == null || v.trim().length < 2)
                                                  ? 'أدخل الاسم الكامل'
                                                  : null,
                                        ),
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('login-name-hidden'),
                                      ),
                              ),
                              TextFormField(
                                key: const Key('auth_email'),
                                controller: email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'البريد الإلكتروني',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: (v) =>
                                    (v == null || !v.contains('@'))
                                        ? 'أدخل بريداً صالحاً'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: const Key('auth_password'),
                                controller: password,
                                obscureText: obscurePassword,
                                textInputAction: TextInputAction.done,
                                autofillHints: registerMode
                                    ? const [AutofillHints.newPassword]
                                    : const [AutofillHints.password],
                                onFieldSubmitted: (_) =>
                                    controller.busy ? null : _submit(),
                                decoration: InputDecoration(
                                  labelText: 'كلمة المرور',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: obscurePassword
                                        ? 'إظهار كلمة المرور'
                                        : 'إخفاء كلمة المرور',
                                    onPressed: () => setState(
                                      () => obscurePassword = !obscurePassword,
                                    ),
                                    icon: Icon(
                                      obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.length < 8)
                                        ? '8 أحرف على الأقل'
                                        : null,
                              ),
                              if (controller.error != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.errorContainer,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: cs.onErrorContainer,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          controller.error!,
                                          style: TextStyle(
                                            color: cs.onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (!registerMode) ...[
                                const SizedBox(height: 14),
                                Container(
                                  key: const Key('demo_account_card'),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: cs.secondaryContainer.withValues(alpha: .55),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: cs.secondary.withValues(alpha: .18),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.science_outlined,
                                            color: cs.secondary,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'حساب التجربة الجاهز',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const SelectableText(
                                        'demo@smartshipping.sa  •  Demo@12345',
                                        textDirection: TextDirection.ltr,
                                      ),
                                      const SizedBox(height: 10),
                                      OutlinedButton.icon(
                                        key: const Key('fill_demo_account'),
                                        onPressed: controller.busy
                                            ? null
                                            : () {
                                                email.text = 'demo@smartshipping.sa';
                                                password.text = 'Demo@12345';
                                                setState(() {});
                                              },
                                        icon: const Icon(Icons.auto_fix_high),
                                        label: const Text('تعبئة بيانات التجربة'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                key: const Key('auth_submit'),
                                onPressed: controller.busy ? null : _submit,
                                icon: controller.busy
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: cs.onPrimary,
                                        ),
                                      )
                                    : Icon(
                                        registerMode
                                            ? Icons.person_add_alt_1
                                            : Icons.login,
                                      ),
                                label: Text(
                                  registerMode ? 'إنشاء الحساب' : 'دخول آمن',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'الحساب والجلسة محفوظان محلياً على الجهاز.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!formKey.currentState!.validate()) return;
    final c = context.read<AppController>();
    if (registerMode) {
      await c.register(name.text, email.text, password.text);
    } else {
      await c.login(email.text, password.text);
    }
  }
}
