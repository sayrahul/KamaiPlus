# -*- coding: utf-8 -*-
"""Generates lib/core/localization/app_strings.dart from i18n_data.py.

Run:  python tool/gen_i18n.py

Why generated rather than hand-edited: the previous app_strings.dart was a
per-language map, so every new string meant editing nine separate places and a
missed one was invisible. It listed Gujarati as supported and had no Gujarati
map at all, which silently served English. Here every language for a string
sits on one line, and `flutter test test/localization_test.dart` fails if any
row is short.
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import i18n_data as data  # noqa: E402

OUT = os.path.join(HERE, "..", "lib", "core", "localization", "app_strings.dart")

# name, nativeName, flag, isBeta
#
# Beta marks a language nobody on the team can read. The translations are
# careful, but "careful" is not "reviewed by a speaker", and a shopkeeper
# deserves to know which of those two they are getting.
LANG_META = {
    "en": ("English", "English", "\U0001F1EC\U0001F1E7", False),
    "hi": ("Hindi", "हिंदी", "\U0001F1EE\U0001F1F3", False),
    "mr": ("Marathi", "मराठी", "\U0001F1EE\U0001F1F3", False),
    "gu": ("Gujarati", "ગુજરાતી", "\U0001F1EE\U0001F1F3", True),
    "ta": ("Tamil", "தமிழ்", "\U0001F1EE\U0001F1F3", True),
    "te": ("Telugu", "తెలుగు", "\U0001F1EE\U0001F1F3", True),
    "kn": ("Kannada", "ಕನ್ನಡ", "\U0001F1EE\U0001F1F3", True),
    "bn": ("Bengali", "বাংলা", "\U0001F1EE\U0001F1F3", True),
    "pa": ("Punjabi", "ਪੰਜਾਬੀ", "\U0001F1EE\U0001F1F3", True),
}

# Text-to-speech locale per language, for the soundbox. Falls back to en-IN.
TTS_LOCALE = {
    "en": "en-IN", "hi": "hi-IN", "mr": "mr-IN", "gu": "gu-IN", "ta": "ta-IN",
    "te": "te-IN", "kn": "kn-IN", "bn": "bn-IN", "pa": "pa-IN",
}


def dart_str(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def main():
    langs = data.LANGS
    for code in langs:
        if code not in LANG_META:
            raise SystemExit("No metadata for language: " + code)

    total = 0
    for section, entries in data.T.items():
        for key, values in entries.items():
            if len(values) != len(langs):
                raise SystemExit(
                    "'%s' has %d values, expected %d" % (key, len(values), len(langs))
                )
            if any(not v.strip() for v in values):
                raise SystemExit("'%s' has an empty translation" % key)
            total += 1

    out = []
    w = out.append
    w("// GENERATED FILE - DO NOT EDIT BY HAND.")
    w("//")
    w("// Source:    tool/i18n_data.py")
    w("// Regenerate: python tool/gen_i18n.py")
    w("//")
    w("// %d keys x %d languages = %d strings." % (total, len(langs), total * len(langs)))
    w("//")
    w("// Editing this file directly means the next regeneration silently discards")
    w("// your change. Add the string to tool/i18n_data.py instead, with all")
    w("// %d languages on one line, and run the generator." % len(langs))
    w("")
    w("class AppLanguage {")
    w("  final String code;")
    w("  final String name;")
    w("  final String nativeName;")
    w("  final String flag;")
    w("")
    w("  /// True for a language nobody on the team reads.")
    w("  ///")
    w("  /// The translations are careful, but careful is not the same as reviewed")
    w("  /// by a speaker, and the picker says so rather than presenting every")
    w("  /// language as equally trustworthy.")
    w("  final bool isBeta;")
    w("")
    w("  /// Locale handed to the platform text-to-speech engine, so the soundbox")
    w("  /// announces takings in the language the merchant chose.")
    w("  final String ttsLocale;")
    w("")
    w("  const AppLanguage({")
    w("    required this.code,")
    w("    required this.name,")
    w("    required this.nativeName,")
    w("    required this.flag,")
    w("    this.isBeta = false,")
    w("    this.ttsLocale = 'en-IN',")
    w("  });")
    w("}")
    w("")
    w("class AppStrings {")
    w("  static const List<AppLanguage> supportedLanguages = [")
    for code in langs:
        name, native, flag, beta = LANG_META[code]
        w("    AppLanguage(")
        w("      code: %s," % dart_str(code))
        w("      name: %s," % dart_str(name))
        w("      nativeName: %s," % dart_str(native))
        w("      flag: %s," % dart_str(flag))
        w("      isBeta: %s," % ("true" if beta else "false"))
        w("      ttsLocale: %s," % dart_str(TTS_LOCALE.get(code, "en-IN")))
        w("    ),")
    w("  ];")
    w("")
    w("  /// Position of each language inside every row of [_t].")
    w("  static const Map<String, int> _langIndex = {")
    for i, code in enumerate(langs):
        w("    %s: %d," % (dart_str(code), i))
    w("  };")
    w("")
    w("  /// key -> [%s]" % ", ".join(langs))
    w("  ///")
    w("  /// One row per string with every language on it, so a missing")
    w("  /// translation is a short row the test catches, not a key quietly")
    w("  /// absent from one of nine separate maps.")
    w("  static const Map<String, List<String>> _t = {")
    for section, entries in data.T.items():
        w("    // ---- %s ----" % section)
        for key, values in entries.items():
            joined = ", ".join(dart_str(v) for v in values)
            w("    %s: [%s]," % (dart_str(key), joined))
    w("  };")
    w("")
    w("  /// Every key this app knows about. Used by the localization test.")
    w("  static Iterable<String> get allKeys => _t.keys;")
    w("")
    w("  /// Looks up [key] in [lang], falling back to English.")
    w("  ///")
    w("  /// A const map lookup, so switching language is a rebuild and nothing")
    w("  /// more — no file IO, no async, no network. That is what keeps the")
    w("  /// switch instant.")
    w("  static String get(String key, {String lang = 'en'}) {")
    w("    final row = _t[key];")
    w("    // An unknown key returns itself rather than blank: a screen showing")
    w("    // 'checkout_v2' is a bug report, a screen showing nothing is a mystery.")
    w("    if (row == null) return key;")
    w("    final index = _langIndex[lang] ?? 0;")
    w("    if (index >= row.length) return row[0];")
    w("    final value = row[index];")
    w("    return value.isEmpty ? row[0] : value;")
    w("  }")
    w("")
    w("  static AppLanguage languageFor(String code) {")
    w("    for (final l in supportedLanguages) {")
    w("      if (l.code == code) return l;")
    w("    }")
    w("    return supportedLanguages.first;")
    w("  }")
    w("}")
    w("")

    io.open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print("Wrote %s" % os.path.normpath(OUT))
    print("%d keys x %d languages = %d strings" % (total, len(langs), total * len(langs)))


if __name__ == "__main__":
    main()
