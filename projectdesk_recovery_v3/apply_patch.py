from pathlib import Path
import re

root = Path("android/app/src/main/kotlin/com/mographikod/projectdesk_recovery")

for p in root.glob("*.kt"):
    s = p.read_text()
    s = s.replace(
        'execSQL("PRAGMA journal_mode=DELETE")',
        'rawQuery("PRAGMA journal_mode=DELETE", null).use { it.moveToFirst() }',
    )
    p.write_text(s)

p = root / "RecoveryAccessibilityService.kt"
s = p.read_text()

needle = '''                val descriptors = collectAllProjectDescriptors()
                saveState("running", "تم العثور على ${descriptors.size} مشروع. بدأت القراءة…", descriptors.size, 0, "")'''
replacement = '''                val descriptors = collectAllProjectDescriptors()
                if (descriptors.isEmpty()) {
                    throw IllegalStateException("لم أستطع اكتشاف بطاقات المشاريع. افتح شاشة المشاريع وتأكد من ظهورها ثم أعد المحاولة")
                }
                saveState("running", "تم العثور على ${descriptors.size} مشروع. بدأت القراءة…", descriptors.size, 0, "")'''
if needle not in s:
    raise SystemExit("descriptor guard marker not found")
s = s.replace(needle, replacement)

new_open = r'''    private fun openProject(target: ProjectDescriptor): Boolean {
        ensureProjectsScreen()
        scrollToStart()
        var stale = 0
        repeat(120) {
            checkCancelled()
            val root = rootInActiveWindow ?: return@repeat
            val cards = findProjectCards(root)
            val match = cards.firstOrNull { it.signature == target.signature }
                ?: cards.firstOrNull {
                    normalize(it.shortTitle) == normalize(target.shortTitle) &&
                        normalize(it.studentHint) == normalize(target.studentHint)
                }
                ?: cards.firstOrNull {
                    normalize(it.shortTitle) == normalize(target.shortTitle)
                }

            val titleNodes = findNodesByText(root, target.shortTitle)
            val exactTitle = titleNodes.firstOrNull {
                normalize(it.text?.toString().orEmpty()) == normalize(target.shortTitle)
            }
            val clicked = clickNode(exactTitle ?: match?.node)
            if (clicked) {
                if (waitUntil(7000) {
                        val current = rootInActiveWindow
                        current != null &&
                            containsText(current, "الملخص") &&
                            containsText(current, "التسليم")
                    }) return true
            }

            val scroll = findPrimaryScrollable(root)
            val moved = scroll?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) == true
            stale = if (!moved) stale + 1 else 0
            if (stale >= 2) return false
            sleep(500)
        }
        return false
    }'''

s, n = re.subn(
    r'    private fun openProject\(target: ProjectDescriptor\): Boolean \{.*?\n    \}\n\n    private fun extractCurrentProject',
    new_open + '\n\n    private fun extractCurrentProject',
    s,
    count=1,
    flags=re.S,
)
if n != 1:
    raise SystemExit("openProject replacement failed")

new_cards = r'''    private fun findProjectCards(root: AccessibilityNodeInfo): List<ProjectDescriptor> {
        val partNodes = mutableListOf<AccessibilityNodeInfo>()
        walk(root) { node ->
            val text = node.text?.toString()?.trim().orEmpty()
            if (text == "Part 1" || text == "Part 2") partNodes.add(node)
        }

        val out = mutableListOf<ProjectDescriptor>()
        val seen = mutableSetOf<String>()
        val noise = setOf(
            "المشاريع", "مشروع جديد", "إضافة مشروع", "الكل",
            "Part 1", "Part 2", "قيد التنفيذ", "تعديلات", "مكتمل",
            "AI", "ذكاء اصطناعي"
        )

        for (partNode in partNodes) {
            val partText = partNode.text?.toString()?.trim().orEmpty()
            var cursor: AccessibilityNodeInfo? = partNode.parent
            var card: AccessibilityNodeInfo? = null
            var texts: List<String> = emptyList()
            var depth = 0

            while (cursor != null && depth < 9) {
                val currentTexts = descendantTexts(cursor).filter { it.isNotBlank() }
                val meaningful = currentTexts.filterNot {
                    it in noise ||
                        statuses.contains(it) ||
                        it.matches(Regex("\\d{1,3}%")) ||
                        it.startsWith("تقدم ") ||
                        it.startsWith("عدد التعديلات")
                }
                val hasState = currentTexts.any {
                    statuses.contains(it) || it.matches(Regex("\\d{1,3}%"))
                }
                val b = bounds(cursor)

                if (currentTexts.contains(partText) &&
                    meaningful.isNotEmpty() &&
                    (hasState || meaningful.size >= 2) &&
                    currentTexts.size <= 22 &&
                    b.width() > 120 &&
                    b.height() > 50) {
                    card = cursor
                    texts = currentTexts
                    break
                }
                cursor = cursor.parent
                depth++
            }

            val node = card ?: continue
            val candidates = texts.filterNot {
                it in noise ||
                    statuses.contains(it) ||
                    it.matches(Regex("\\d{1,3}%")) ||
                    it.startsWith("تقدم ") ||
                    it.startsWith("عدد التعديلات")
            }.filter { it.length in 2..180 }

            if (candidates.isEmpty()) continue

            val short = candidates.first()
            if (short in setOf("الكل", "Part 1", "Part 2")) continue

            val original = if (candidates.size >= 3) candidates[1] else ""
            val student = when {
                candidates.size >= 4 -> candidates[candidates.size - 2]
                candidates.size >= 2 -> candidates.last()
                else -> ""
            }
            val branch = if (candidates.size >= 4) candidates.last() else ""
            val status = texts.firstOrNull { statuses.contains(it) }.orEmpty()
            val progressText = texts.firstOrNull {
                it.matches(Regex("\\d{1,3}%"))
            }.orEmpty()
            val progress = progressText.removeSuffix("%").toIntOrNull() ?: 0
            val signature = listOf(short, original, student, branch, partText)
                .joinToString("|") { normalize(it) }

            if (seen.add(signature)) {
                out.add(
                    ProjectDescriptor(
                        node,
                        signature,
                        short,
                        original,
                        student,
                        branch,
                        if (partText.endsWith("2")) 2 else 1,
                        status.ifBlank { "جديد" },
                        progress,
                    )
                )
            }
        }

        return out.sortedBy { bounds(it.node).top }
    }'''

s, n = re.subn(
    r'    private fun findProjectCards\(root: AccessibilityNodeInfo\): List<ProjectDescriptor> \{.*?\n    \}\n\n    private data class ProjectDescriptor',
    new_cards + '\n\n    private data class ProjectDescriptor',
    s,
    count=1,
    flags=re.S,
)
if n != 1:
    raise SystemExit("findProjectCards replacement failed")

p.write_text(s)

p = root / "RecoveryBackupBuilder.kt"
s = p.read_text()
needle = 'val projects = root.optJSONArray("projects") ?: throw IllegalArgumentException("ملف الاستعادة لا يحتوي مشاريع")'
replacement = needle + '\n        if (projects.length() == 0) throw IllegalStateException("لم يتم استخراج أي مشروع. لن يتم إنشاء نسخة فارغة")'
if needle not in s:
    raise SystemExit("backup project marker not found")
s = s.replace(needle, replacement)
p.write_text(s)

p = root / "MainActivity.kt"
s = p.read_text()
needle = '''                        if (data.isBlank()) result.error("NO_DATA", "لا توجد بيانات مستعادة", null)
                        else result.success(RecoveryBackupBuilder.create(this, data).absolutePath)'''
replacement = '''                        val prefs = getSharedPreferences(RecoveryAccessibilityService.PREFS, Context.MODE_PRIVATE)
                        val recovered = prefs.getInt("recovered", 0)
                        if (data.isBlank() || recovered <= 0) {
                            result.error("NO_DATA", "لم يتم استخراج أي مشروع. أعد عملية الاستعادة أولًا", null)
                        } else {
                            result.success(RecoveryBackupBuilder.create(this, data).absolutePath)
                        }'''
if needle not in s:
    raise SystemExit("MainActivity buildBackup marker not found")
s = s.replace(needle, replacement)
p.write_text(s)
