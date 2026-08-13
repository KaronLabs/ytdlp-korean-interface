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
STATE_TOKENS_HEADER = SOURCE_ROOT / "state_tokens.hpp"
SETTINGS_JSON_HEADER = SOURCE_ROOT / "settings_json.hpp"
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


def direct_i18n_calls():
    direct_call = re.compile(
        r"\s*(?P<key>" + STRING_LITERAL + r")\s*,\s*"
        r"(?P<fallback>" + STRING_LITERAL + r")\s*",
        re.DOTALL,
    )
    calls = {}
    failures = []
    for path, text in source_texts().items():
        for offset, arguments in i18n_tr_calls(text):
            location = f"{path.relative_to(REPOSITORY_ROOT)}:{text.count(chr(10), 0, offset) + 1}"
            if arguments is None:
                failures.append(f"{location}: unclosed i18n::tr()")
                continue
            match = direct_call.fullmatch(arguments)
            if not match:
                failures.append(f"{location}: i18n::tr() must have two direct string literals")
                continue
            key = json.loads(match.group("key"))
            fallback = json.loads(match.group("fallback"))
            if not fallback:
                failures.append(f"{location}: {key}: empty English fallback")
            if key in calls:
                failures.append(f"{location}: duplicate key {key} (first at {calls[key][1]})")
            else:
                calls[key] = (fallback, location)

    resource_path = SOURCE_ROOT / "ytdlp-interface.rc"
    resource_text = resource_path.read_text(encoding="utf-8-sig", errors="replace")
    resource = re.search(r'VALUE\s+"FileDescription",\s+"([^"]+)"', resource_text)
    if resource:
        calls["windows.file_description"] = (
            resource.group(1),
            f"{resource_path.relative_to(REPOSITORY_ROOT)}:FileDescription",
        )
    else:
        failures.append("ytdlp-interface/ytdlp-interface.rc: missing FileDescription resource")
    return calls, failures


def placeholders(value):
    return sorted(re.findall(r"\{[A-Za-z_][A-Za-z0-9_]*\}", value))


def valid_nana_markup(value):
    stack = []
    for token in re.finditer(r"</>|</([A-Za-z][A-Za-z0-9_-]*)>|<([A-Za-z][A-Za-z0-9_-]*)[^<>\n]*>", value):
        if token.group(0) == "</>":
            if not stack:
                return False
            stack.pop()
        elif token.group(1):
            if not stack or stack.pop() != token.group(1):
                return False
        else:
            stack.append(token.group(2))
    return "<" not in re.sub(r"</>|</[A-Za-z][A-Za-z0-9_-]*>|<[A-Za-z][A-Za-z0-9_-]*[^<>\n]*>", "", value) and not stack


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
    def test_task_3_settings_round_trip_persists_queue_states_without_sidecar(self):
        self.assertTrue(SETTINGS_JSON_HEADER.is_file(), "missing GUI-free settings serialization")
        source = SETTINGS_JSON_HEADER.read_text(encoding="utf-8")
        self.assertIn('j["unfinished_queue_states"]', source)
        self.assertIn("unfinished_queue_states", source)
        gui_source = (SOURCE_ROOT / "gui.hpp").read_text(encoding="utf-8-sig")
        self.assertIn("conf.unfinished_queue_states", gui_source)
        self.assertIn("queue_item_state::skipped", gui_source)

    def test_task_3_state_tokens_preserve_queue_state_without_visible_caption_logic(self):
        self.assertTrue(STATE_TOKENS_HEADER.is_file(), "missing stable state token header")
        source = STATE_TOKENS_HEADER.read_text(encoding="utf-8")
        for token in ("queued", "active", "stopped", "done", "error", "skipped"):
            with self.subTest(token=token):
                self.assertIn(f'"{token}"', source)
        self.assertIn("queue_item_state_from_token", source)
        self.assertIn("queue_item_state_from_legacy_status", source)
        self.assertIn('j["queue_state"]', (SOURCE_ROOT / "queue.cpp").read_text(encoding="utf-8-sig"))
        self.assertIn('j["queue_state"]', (SOURCE_ROOT / "forms" / "form_loading.cpp").read_text(encoding="utf-8-sig"))
        self.assertIn("queue_item_state_from_legacy_status", (SOURCE_ROOT / "gui.cpp").read_text(encoding="utf-8-sig"))

    def test_task_3_settings_language_defaults_persists_and_falls_back(self):
        header = (SOURCE_ROOT / "types.hpp").read_text(encoding="utf-8-sig")
        source = (SOURCE_ROOT / "types.cpp").read_text(encoding="utf-8-sig")
        self.assertRegex(header, r'std::string\s+language\s*\{\s*"en-US"\s*\}')
        self.assertIn('j["language"] = language;', source)
        self.assertIn('return language == "ko-KR" ? language : "en-US";', STATE_TOKENS_HEADER.read_text(encoding="utf-8"))
        self.assertIn("settings_json_t", source)
        self.assertIn("normalized_language", SETTINGS_JSON_HEADER.read_text(encoding="utf-8"))
        self.assertIn('#include "settings_json.hpp"', header)

    def test_task_3_loads_selected_catalog_before_gui_construction(self):
        source = (SOURCE_ROOT / "main.cpp").read_text(encoding="utf-8-sig", errors="replace")
        self.assertIn('i18n::load_catalog', source)
        load = source.index('i18n::load_catalog')
        construct = source.index('GUI gui;')
        self.assertLess(load, construct)
        self.assertIn('appdir / "locales" / "ko-KR.json"', source)
        self.assertIn('localization.log', source)
        self.assertIn('i18n::reset_for_tests()', source)

    def test_task_3_behavior_never_compares_visible_control_captions(self):
        sources = {
            path.name: path.read_text(encoding="utf-8-sig", errors="replace")
            for path in (
                SOURCE_ROOT / "gui.cpp",
                SOURCE_ROOT / "gui_make.cpp",
                SOURCE_ROOT / "outbox.cpp",
                SOURCE_ROOT / "queue.cpp",
                SOURCE_ROOT / "forms" / "form_formats.cpp",
                SOURCE_ROOT / "forms" / "form_settings.cpp",
            )
        }
        forbidden = ("done", "queue", "Audio only", "Video only", "Update", "Cancel")
        for name, source in sources.items():
            for caption in forbidden:
                with self.subTest(source=name, caption=caption):
                    self.assertNotRegex(
                        source,
                        rf'(?:caption\s*\(\s*\)|text\s*\(\s*3\s*\)).{{0,80}}(?:==|!=|\.find\s*\()\s*"{re.escape(caption)}"',
                    )

        gui_source = sources["gui.cpp"]
        queue_source = sources["queue.cpp"]
        header = (SOURCE_ROOT / "gui.hpp").read_text(encoding="utf-8-sig")
        bottom_source = (SOURCE_ROOT / "gui_bottom.cpp").read_text(encoding="utf-8-sig")
        self.assertNotIn('progtext.find(" of ")', gui_source)
        self.assertIn("playlist_item_index", header)
        self.assertIn("bottom.playlist_item_index", gui_source)
        self.assertNotIn('item.text(2).find("[live event scheduled to begin in")', queue_source)
        self.assertIn("live_scheduled", header)
        self.assertIn("bottom.live_scheduled", queue_source)
        self.assertIn('if(j.contains("live_scheduled"))', bottom_source)
        self.assertIn('live_scheduled = j["live_scheduled"];', bottom_source)
        self.assertIn("else live_scheduled = false;", bottom_source)
        self.assertIn('j["live_scheduled"] = live_scheduled;', bottom_source)
        self.assertIn("playlist_menu_pos", header)
        self.assertIn("nana::listbox::index_pair playlist_item_pos", header)
        self.assertIn("playlist_item_pos_valid", header)
        self.assertNotIn("vidsel_item = {&m, sel.front().item}", queue_source)
        self.assertIn("vidsel_item.playlist_item_pos.cat == list_item.pos().cat", gui_source)
        self.assertIn("vidsel_item.playlist_item_pos.item == list_item.pos().item", gui_source)
        self.assertIn("vidsel_item.playlist_item_pos_valid", gui_source)
        self.assertRegex(gui_source, r"m\.size\(\)\s*-\s*vidsel_item\.playlist_menu_pos\s*>=\s*4")

        def restored_live_scheduled(data):
            return data.get("live_scheduled", False)

        self.assertFalse(restored_live_scheduled({}))
        self.assertTrue(restored_live_scheduled({"live_scheduled": True}))

    def test_i18n_source_and_header_exist(self):
        self.assertTrue(I18N_SOURCE.is_file(), f"missing i18n source: {I18N_SOURCE}")
        self.assertTrue(I18N_HEADER.is_file(), f"missing i18n header: {I18N_HEADER}")

    def test_i18n_header_declares_localization_core_api(self):
        header = I18N_HEADER.read_text(encoding="utf-8")
        for declaration in (
            r"struct\s+load_result",
            r"bool\s+catalog_loaded",
            r"std::vector<diagnostic>\s+diagnostics",
            r"load_result\s+load_catalog\s*\(",
            r"std::string\s+tr\s*\(",
            r"std::string\s+active_locale\s*\(\s*\)",
            r"void\s+reset_for_tests\s*\(\s*\)",
        ):
            with self.subTest(declaration=declaration):
                self.assertRegex(header, declaration)

    def test_recovered_catalog_has_524_nonempty_string_entries(self):
        strings = recovered_strings()
        self.assertEqual(524, len(strings))
        self.assertTrue(all(isinstance(value, str) and value for value in strings.values()))

    def test_every_catalog_key_has_a_source_reference(self):
        referenced = set(direct_i18n_calls()[0])
        missing = [
            key
            for key in recovered_strings()
            if key not in referenced
        ]
        self.assertEqual([], missing, f"catalog keys have no tr() source references: {missing}")

    def test_catalog_and_active_i18n_calls_have_exact_parity(self):
        catalog = recovered_strings()
        calls, failures = direct_i18n_calls()
        self.assertEqual([], failures)
        self.assertEqual(524, len(catalog))
        self.assertEqual(524, len(calls))
        self.assertEqual(set(catalog), set(calls))
        for key in sorted(catalog):
            fallback, location = calls[key]
            with self.subTest(key=key, location=location):
                self.assertTrue(fallback)
                self.assertEqual(placeholders(catalog[key]), placeholders(fallback))
                self.assertTrue(valid_nana_markup(catalog[key]))

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

    def test_product_build_does_not_require_atl_for_taskbar_com(self):
        header = (SOURCE_ROOT / "gui.hpp").read_text(encoding="utf-8-sig")
        source = (SOURCE_ROOT / "gui_make.cpp").read_text(encoding="utf-8-sig")

        self.assertNotIn("<atlbase.h>", header)
        self.assertNotIn("CComPtr", header)
        self.assertIn("ITaskbarList3 *i_taskbar {nullptr};", header)
        self.assertIn("IID_PPV_ARGS(&i_taskbar)", source)
        self.assertIn("i_taskbar = nullptr;", source)

    def test_windows_process_runner_waits_for_direct_child_not_process_tree(self):
        scripts = ((REPOSITORY_ROOT / "tools" / "build-candidate.ps1"),)
        for script in scripts:
            source = script.read_text(encoding="utf-8-sig")
            with self.subTest(script=script.name):
                self.assertNotIn("-Wait -PassThru", source)
                self.assertIn("$process.Handle | Out-Null", source)
                self.assertIn("$process.WaitForExit()", source)
                self.assertIn("$process.Refresh()", source)

    def test_smoke_entrypoint_preserves_parameters_across_dot_sourcing(self):
        source = (REPOSITORY_ROOT / "tools" / "smoke-localhost.ps1").read_text(encoding="utf-8-sig")

        self.assertIn("$smokeRun = $Run", source)
        self.assertIn("$smokeParentRuntime = $ParentRuntime", source)
        self.assertIn("if (-not $smokeRun)", source)
        self.assertIn("-ParentRuntime $smokeParentRuntime", source)
        self.assertIn("[string] $PythonPath", source)
        self.assertIn("-Arguments @('--version') -Name 'Python runtime check'", source)

    def test_task_7_forms_qualify_widgets_namespace_against_nana_widgets(self):
        form_paths = (
            SOURCE_ROOT / "forms" / "form_subs.cpp",
            SOURCE_ROOT / "forms" / "form_input.cpp",
            SOURCE_ROOT / "forms" / "form_suspend.cpp",
            SOURCE_ROOT / "forms" / "form_colors.cpp",
        )
        unqualified_widgets = re.compile(r"(?<!:)\bwidgets::")
        for path in form_paths:
            source = path.read_text(encoding="utf-8-sig", errors="replace")
            with self.subTest(path=path.name):
                self.assertEqual(
                    [],
                    unqualified_widgets.findall(source),
                    "using namespace nana makes unqualified widgets:: ambiguous with nana::widgets",
                )

    def test_task_7_settings_uses_title_and_combox_value_apis(self):
        source = (SOURCE_ROOT / "forms" / "form_settings.cpp").read_text(
            encoding="utf-8-sig", errors="replace"
        )

        self.assertIn(
            'widgets::Title libtitle {about, i18n::tr("about.libraries", "*  Libraries used  *")}',
            source,
        )
        self.assertIn(
            'kbtitle {about, i18n::tr("about.shortcuts", "*  Keyboard shortcuts  *")}',
            source,
        )
        self.assertNotIn('to_wstring(i18n::tr("about.libraries"', source)
        self.assertNotIn('to_wstring(i18n::tr("about.shortcuts"', source)
        self.assertIn('conf.language = arg.widget.option() == 1 ? "ko-KR" : "en-US";', source)
        self.assertNotIn("arg.widget->option()", source)
