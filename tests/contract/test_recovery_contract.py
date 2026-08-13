import json
import os
import re
import subprocess
import unittest
from pathlib import Path, PurePosixPath


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "ytdlp-interface"
I18N_SOURCE = SOURCE_ROOT / "i18n.cpp"
I18N_HEADER = SOURCE_ROOT / "i18n.hpp"
STRING_LITERAL = r'"(?:[^"\\]|\\.)*"'
FORBIDDEN_ARTIFACT_COMPONENTS = {
    ".superpowers",
    ".vs",
    "x64",
    "Debug",
    "Release",
    "candidate-runtime",
    "smoke-evidence",
    "backups",
    "provenance-staging",
    "bit7z",
    "nana",
    "libpng",
    "libjpeg-turbo-3.1.2",
    "dependencies",
}
FORBIDDEN_ARTIFACT_EXTENSIONS = {".dll", ".exe", ".exp", ".idb", ".ilk", ".lib", ".obj", ".pdb"}


def recovered_catalog_path():
    value = os.environ.get("RECOVERED_CATALOG")
    if not value:
        raise AssertionError("RECOVERED_CATALOG must name the recovered catalog")
    return (REPOSITORY_ROOT / value).resolve()


def recovered_strings():
    with recovered_catalog_path().open(encoding="utf-8") as catalog_file:
        return json.load(catalog_file)["strings"]


def source_texts():
    return {
        path: path.read_text(encoding="utf-8-sig", errors="replace")
        for path in SOURCE_ROOT.rglob("*.*pp")
        if path.is_file()
    }


def skip_noncode_token(text, index):
    if text.startswith("//", index):
        search_start = index + 2
        while True:
            newline = text.find("\n", search_start)
            if newline == -1:
                return len(text)
            escaped_newline = text[newline - 1] == "\\" or (
                newline >= 2 and text[newline - 1] == "\r" and text[newline - 2] == "\\"
            )
            if not escaped_newline:
                return newline
            search_start = newline + 1
    if text.startswith("/*", index):
        closing = text.find("*/", index + 2)
        return len(text) if closing == -1 else closing + 2
    if text.startswith('R"', index):
        delimiter_end = text.find("(", index + 2)
        if delimiter_end != -1:
            delimiter = text[index + 2 : delimiter_end]
            closing = text.find(")" + delimiter + '"', delimiter_end + 1)
            return len(text) if closing == -1 else closing + len(delimiter) + 2
    if text[index] in "\"'":
        quote = text[index]
        index += 1
        while index < len(text):
            if text[index] == "\\":
                index += 2
            elif text[index] == quote:
                return index + 1
            else:
                index += 1
    return index + 1


def comments_as_whitespace(text):
    characters = list(text)
    index = 0
    while index < len(text):
        if text.startswith("//", index):
            end = skip_noncode_token(text, index)
            for cursor in range(index, end):
                if characters[cursor] != "\n":
                    characters[cursor] = " "
            index = end
        elif text.startswith("/*", index):
            end = skip_noncode_token(text, index)
            for cursor in range(index, end):
                if characters[cursor] != "\n":
                    characters[cursor] = " "
            index = end
        elif text.startswith('R"', index) or text[index] in "\"'":
            index = skip_noncode_token(text, index)
        else:
            index += 1
    return "".join(characters)


def inactive_if_zero_arms_as_whitespace(text):
    characters = list(text)
    branches = []

    def condition_state(condition):
        condition = condition.strip()
        if condition == "0":
            return False
        if condition == "1":
            return True
        return None

    index = 0
    while index < len(text):
        if index == 0 or text[index - 1] == "\n":
            directive_start = index
            while directive_start < len(text) and text[directive_start] in " \t\r":
                directive_start += 1
            if directive_start < len(text) and text[directive_start] == "#":
                line_end = text.find("\n", directive_start)
                if line_end == -1:
                    line_end = len(text)
                directive = re.match(
                    r"#[ \t]*(if|elif|else|endif)\b(.*)",
                    text[directive_start:line_end],
                )
                if directive:
                    for cursor in range(index, line_end):
                        characters[cursor] = " "
                    name, condition = directive.groups()
                    if name == "if":
                        selected = condition_state(condition)
                        branches.append([selected is not False, selected])
                    elif name == "elif" and branches:
                        active, selected = branches[-1]
                        candidate = condition_state(condition)
                        if selected is True:
                            branches[-1][0] = False
                        elif selected is False:
                            branches[-1] = [candidate is not False, candidate]
                        else:
                            branches[-1] = [True, None]
                    elif name == "else" and branches:
                        active, selected = branches[-1]
                        branches[-1] = [selected is not True, True if selected is False else selected]
                    elif name == "endif" and branches:
                        branches.pop()
                    index = line_end
                    continue
        if any(not active for active, _ in branches):
            if characters[index] != "\n":
                characters[index] = " "
            index += 1
        elif text.startswith('R"', index) or text[index] in "\"'":
            index = skip_noncode_token(text, index)
        else:
            index += 1
    return "".join(characters)


def i18n_tr_calls(text):
    text = inactive_if_zero_arms_as_whitespace(comments_as_whitespace(text))
    index = 0
    token = "i18n::tr"
    while index < len(text):
        if text.startswith(("//", "/*", 'R"'), index) or text[index] in "\"'":
            index = skip_noncode_token(text, index)
            continue
        if text.startswith(token, index) and (index == 0 or not (text[index - 1].isalnum() or text[index - 1] == "_")):
            opening = index + len(token)
            while opening < len(text) and text[opening].isspace():
                opening += 1
            if opening < len(text) and text[opening] == "(":
                depth = 1
                cursor = opening + 1
                while cursor < len(text) and depth:
                    if text.startswith(("//", "/*", 'R"'), cursor) or text[cursor] in "\"'":
                        cursor = skip_noncode_token(text, cursor)
                        continue
                    if text[cursor] == "(":
                        depth += 1
                    elif text[cursor] == ")":
                        depth -= 1
                    cursor += 1
                yield index, None if depth else text[opening + 1 : cursor - 1]
                index = cursor
                continue
        index += 1


def is_tracked_runtime_artifact(path):
    parts = PurePosixPath(path).parts
    return (
        bool(parts)
        and (
            any(component in FORBIDDEN_ARTIFACT_COMPONENTS for component in parts)
            or Path(path).suffix.lower() in FORBIDDEN_ARTIFACT_EXTENSIONS
        )
    )


class RecoveryContractTests(unittest.TestCase):
    def test_i18n_source_and_header_exist(self):
        self.assertTrue(I18N_SOURCE.is_file(), f"missing i18n source: {I18N_SOURCE}")
        self.assertTrue(I18N_HEADER.is_file(), f"missing i18n header: {I18N_HEADER}")

    def test_recovered_catalog_has_524_nonempty_string_entries(self):
        strings = recovered_strings()
        self.assertEqual(524, len(strings))
        self.assertTrue(all(isinstance(value, str) and value for value in strings.values()))

    def test_every_catalog_key_has_a_source_reference(self):
        key_literal = re.compile(r'\s*"(?P<key>[^"\\]+)"')
        referenced = set()
        for text in source_texts().values():
            for _, arguments in i18n_tr_calls(text):
                if arguments:
                    match = key_literal.match(arguments)
                    if match:
                        referenced.add(match.group("key"))
        missing = [
            key
            for key in recovered_strings()
            if key not in referenced
        ]
        self.assertEqual([], missing, f"catalog keys have no tr() source references: {missing}")

    def test_every_tr_call_has_a_nonempty_english_fallback(self):
        direct_call = re.compile(
            r"\s*(?P<key>" + STRING_LITERAL + r")\s*,\s*"
            r"(?P<fallback>" + STRING_LITERAL + r")\s*",
            re.DOTALL,
        )
        sample = (
            '// i18n::tr("comment.key", "Comment")\n'
            '/* i18n::tr("block.key", "Block") */\n'
            'auto label = "i18n::tr(\\\"literal.key\\\", \\\"Literal\\\")";\n'
            'auto raw = R"(i18n::tr("raw.key", "Raw"))";\n'
            "auto character = 'x';\n"
            'i18n::tr("actual.key", "English");\n'
            'i18n::tr /* callee */ ( /* key */ "commented.key" /* comma */ ,\n'
            '    // fallback\n'
            '    "Commented English" /* close */ );\n'
        )
        calls = [arguments for _, arguments in i18n_tr_calls(sample)]
        self.assertEqual(
            '"actual.key", "English"',
            calls[0],
        )
        self.assertEqual(2, len(calls))
        self.assertIsNotNone(direct_call.fullmatch(calls[1]))
        for path, text in source_texts().items():
            for offset, arguments in i18n_tr_calls(text):
                location = f"{path.relative_to(REPOSITORY_ROOT)}:{text.count(chr(10), 0, offset) + 1}"
                with self.subTest(location=location):
                    self.assertIsNotNone(arguments, "i18n::tr() has no closing parenthesis")
                    match = direct_call.fullmatch(arguments)
                    self.assertIsNotNone(
                        match,
                        "i18n::tr() must have exactly two direct string literal arguments",
                    )
                    fallback = match.group("fallback")[1:-1]
                    self.assertTrue(fallback.strip(), "i18n::tr() fallback must not be empty")

    def test_i18n_tr_calls_ignores_backslash_newline_line_comments(self):
        sample = (
            '// ignored \\\r\n'
            'i18n::tr("escaped-comment.key", "Decoy");\r\n'
            'i18n::tr("actual.key", "English");\r\n'
        )

        calls = [arguments for _, arguments in i18n_tr_calls(sample)]

        self.assertEqual(['"actual.key", "English"'], calls)

    def test_i18n_tr_calls_ignores_if_zero_arms_and_scans_else_with_nesting(self):
        sample = (
            '#if 0\n'
            'i18n::tr("disabled.key", "Decoy");\n'
            '#if 0\n'
            'i18n::tr("nested-disabled.key", "Decoy");\n'
            '#else\n'
            'i18n::tr("nested-else-under-disabled.key", "Decoy");\n'
            '#endif\n'
            '#else\n'
            'i18n::tr("enabled.key", "English");\n'
            '#if 0\n'
            'i18n::tr("enabled-nested-disabled.key", "Decoy");\n'
            '#else\n'
            'i18n::tr("enabled-nested-else.key", "English");\n'
            '#endif\n'
            '#endif\n'
        )

        calls = [arguments for _, arguments in i18n_tr_calls(sample)]

        self.assertEqual(
            ['"enabled.key", "English"', '"enabled-nested-else.key", "English"'],
            calls,
        )

    def test_i18n_tr_calls_ignores_else_after_if_one(self):
        sample = (
            '#if 1\n'
            'i18n::tr("enabled.key", "English");\n'
            '#else\n'
            'i18n::tr("disabled-else.key", "Decoy");\n'
            '#endif\n'
        )

        calls = [arguments for _, arguments in i18n_tr_calls(sample)]

        self.assertEqual(['"enabled.key", "English"'], calls)

    def test_runtime_artifacts_are_ignored(self):
        for artifact in (
            ".superpowers/generated.txt",
            "bit7z/extracted.lib",
            "nana/build/output.lib",
            "libpng/x64/output.lib",
            "libjpeg-turbo-3.1.2/out/build/output.lib",
            ".vs/index.db",
            "x64/Release/ytdlp-interface.exe",
            "Debug/ytdlp-interface.pdb",
            "Release/ytdlp-interface.pdb",
            "candidate-runtime/ytdlp-interface.exe",
            "smoke-evidence/window.png",
            "backups/original.exe",
            "provenance-staging/source.txt",
        ):
            with self.subTest(artifact=artifact):
                result = subprocess.run(
                    ["git", "check-ignore", "-q", artifact],
                    cwd=REPOSITORY_ROOT,
                    check=False,
                )
                self.assertEqual(0, result.returncode, f"runtime artifact is not ignored: {artifact}")
        for tracked_path in ("README.md", "docs/superpowers", "ytdlp-interface/gui.cpp"):
            with self.subTest(tracked_path=tracked_path):
                result = subprocess.run(
                    ["git", "check-ignore", "-q", tracked_path],
                    cwd=REPOSITORY_ROOT,
                    check=False,
                )
                self.assertEqual(1, result.returncode, f"source or docs must not be ignored: {tracked_path}")
        tracked = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
        ).stdout.decode().split("\0")
        self.assertTrue(is_tracked_runtime_artifact("nested/.vs/index.db"))
        self.assertTrue(is_tracked_runtime_artifact("nested/smoke-evidence/window.png"))
        self.assertTrue(is_tracked_runtime_artifact("nested/candidate-runtime/app.exe"))
        self.assertTrue(is_tracked_runtime_artifact("docs/candidate-runtime/proof.md"))
        self.assertTrue(is_tracked_runtime_artifact("tests/fixtures/example.exe"))
        self.assertFalse(is_tracked_runtime_artifact("docs/windows-smoke.md"))
        self.assertFalse(is_tracked_runtime_artifact("tests/fixtures/catalog_valid.json"))
        forbidden = [
            path
            for path in tracked
            if is_tracked_runtime_artifact(path)
        ]
        self.assertEqual([], forbidden, f"tracked runtime artifacts are forbidden: {forbidden}")
