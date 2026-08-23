from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    p = Path(path)
    s = p.read_text(encoding='utf-8')
    if old not in s:
        raise SystemExit(f'Expected text not found in {path}: {old[:80]!r}')
    p.write_text(s.replace(old, new), encoding='utf-8')

# auth_service.dart: analyzer-safe control flow and List<int> iterative hash buffer.
path = 'lib/services/auth_service.dart'
replace(path, "    if (existing.isNotEmpty) return;", "    if (existing.isNotEmpty) {\n      return;\n    }")
replace(path, "    if (raw == null) return null;", "    if (raw == null) {\n      return null;\n    }")
replace(path, "    if (id == null) return null;", "    if (id == null) {\n      return null;\n    }")
replace(path, "    if (!_validEmail(normalized)) throw const AuthException('البريد الإلكتروني غير صالح.');", "    if (!_validEmail(normalized)) {\n      throw const AuthException('البريد الإلكتروني غير صالح.');\n    }")
replace(path, "    if (fullName.trim().length < 2) throw const AuthException('أدخل الاسم الكامل.');", "    if (fullName.trim().length < 2) {\n      throw const AuthException('أدخل الاسم الكامل.');\n    }")
replace(path, "    if (password.length < 8) throw const AuthException('كلمة المرور يجب أن تكون 8 أحرف على الأقل.');", "    if (password.length < 8) {\n      throw const AuthException('كلمة المرور يجب أن تكون 8 أحرف على الأقل.');\n    }")
replace(path, "    if (existing.isNotEmpty) throw const AuthException('يوجد حساب بهذا البريد بالفعل.');", "    if (existing.isNotEmpty) {\n      throw const AuthException('يوجد حساب بهذا البريد بالفعل.');\n    }")
replace(path, "    if (rows.isEmpty) throw const AuthException('البريد أو كلمة المرور غير صحيحة.');", "    if (rows.isEmpty) {\n      throw const AuthException('البريد أو كلمة المرور غير صحيحة.');\n    }")
replace(path, "    var bytes = utf8.encode('$salt:$password');", "    List<int> bytes = utf8.encode('$salt:$password');")
replace(path, "    if (aa.length != bb.length) return false;", "    if (aa.length != bb.length) {\n      return false;\n    }")

# results_screen.dart: avoid async-context lint, add braces, final locals, new form API.
path = 'lib/screens/results_screen.dart'
replace(
    path,
    "                      await context.read<AppController>().saveQuote(quote);\n                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الخيار.')));",
    "                      final controller = context.read<AppController>();\n                      final messenger = ScaffoldMessenger.of(context);\n                      await controller.saveQuote(quote);\n                      if (!mounted) {\n                        return;\n                      }\n                      messenger.showSnackBar(\n                        const SnackBar(content: Text('تم حفظ الخيار.')),\n                      );",
)
for old, new in [
    ("      if (trackingOnly && !q.service.tracking) return false;", "      if (trackingOnly && !q.service.tracking) {\n        return false;\n      }"),
    ("      if (doorToDoorOnly && !q.service.doorToDoor) return false;", "      if (doorToDoorOnly && !q.service.doorToDoor) {\n        return false;\n      }"),
    ("      if (codOnly && !q.service.cod) return false;", "      if (codOnly && !q.service.cod) {\n        return false;\n      }"),
    ("      if (exactPriceOnly && !q.isComparable) return false;", "      if (exactPriceOnly && !q.isComparable) {\n        return false;\n      }"),
    ("      if (serviceCategory != null && q.service.serviceCategory != serviceCategory) return false;", "      if (serviceCategory != null && q.service.serviceCategory != serviceCategory) {\n        return false;\n      }"),
    ("      if (maxDays != null && (q.service.etaMax == null || q.service.etaMax! > maxDays!)) return false;", "      if (maxDays != null && (q.service.etaMax == null || q.service.etaMax! > maxDays!)) {\n        return false;\n      }"),
    ("          if (a.price == null && b.price == null) return 0;", "          if (a.price == null && b.price == null) {\n            return 0;\n          }"),
    ("          if (a.price == null) return 1;", "          if (a.price == null) {\n            return 1;\n          }"),
    ("          if (b.price == null) return -1;", "          if (b.price == null) {\n            return -1;\n          }"),
    ("          if (!a.isComparable && b.isComparable) return 1;", "          if (!a.isComparable && b.isComparable) {\n            return 1;\n          }"),
    ("          if (a.isComparable && !b.isComparable) return -1;", "          if (a.isComparable && !b.isComparable) {\n            return -1;\n          }"),
    ("    if (prices.length < 2) return null;", "    if (prices.length < 2) {\n      return null;\n    }"),
    ("    if (max <= min) return null;", "    if (max <= min) {\n      return null;\n    }"),
]:
    replace(path, old, new)
replace(path, "    var out = widget.result.quotes.where((q) {", "    final out = widget.result.quotes.where((q) {")
replace(path, "        value: selected,", "        initialValue: selected,")

print('Round 1 analyzer fixes applied.')
