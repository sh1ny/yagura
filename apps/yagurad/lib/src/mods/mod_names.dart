import 'package:yagura_plugin/yagura_plugin.dart';

/// [title] reduced to `[A-Za-z0-9._-]` (design D7): spaces become `-`, other
/// characters go, runs of `-` become one, and no `-`, `.` or space is left at
/// either end (Windows drops a trailing dot). Empty when nothing is left.
String sanitizeModTitle(String title) {
  final dashed = title.replaceAll(RegExp(r'\s+'), '-');
  final kept = dashed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
  return kept
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
}

/// The staged name of a mod: the plugin's `link_name` template with
/// `{{mod.name_safe}}` set to the sanitised [title]. A [title] that leaves
/// nothing after sanitising falls back to [itemId], the name of a mod whose
/// metadata could not be read.
String renderModName(String linkName, String? title, String itemId) {
  var safe = sanitizeModTitle(title ?? '');
  if (safe.isEmpty) safe = sanitizeModTitle(itemId);
  if (safe.isEmpty) safe = 'mod';
  final out = StringBuffer();
  for (final part in parseTemplate(linkName)) {
    switch (part) {
      case TemplateText(:final text):
        out.write(text);
      case TemplateRef():
        out.write(safe);
    }
  }
  return out.toString();
}

/// [name], or [name] with `-2`, `-3`... when its lower-cased form is in
/// [taken] (names compare case-insensitively on Windows).
String uniqueModName(String name, Set<String> taken) {
  if (!taken.contains(name.toLowerCase())) return name;
  for (var n = 2; ; n++) {
    final candidate = '$name-$n';
    if (!taken.contains(candidate.toLowerCase())) return candidate;
  }
}
