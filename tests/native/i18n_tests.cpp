#include "i18n.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace
{
	int failures {};

	void expect(bool condition, const char *expression, const char *test)
	{
		if(!condition)
		{
			++failures;
			std::cerr << test << ": expected " << expression << '\n';
		}
	}

	struct catalog_file
	{
		std::filesystem::path path;

		catalog_file(const std::string &contents, const char *name)
		{
			path = std::filesystem::temp_directory_path() / (std::string("ytdlp-interface-i18n-") + name + ".json");
			std::ofstream output(path, std::ios::binary);
			output.write(contents.data(), static_cast<std::streamsize>(contents.size()));
		}

		~catalog_file()
		{
			std::error_code error;
			std::filesystem::remove(path, error);
		}
	};

	const std::string valid_catalog {
		R"({"locale":"ko-KR","schemaVersion":1,"strings":{"hello":"안녕하세요","count":"{total}개 중 {current}","markup":"<bold color={accent}>안내</>"}})"
	};

	void test_valid_catalog_and_fallbacks()
	{
		catalog_file catalog(valid_catalog, "valid");
		i18n::reset_for_tests();
		auto result = i18n::load_catalog(catalog.path);
		expect(result.catalog_loaded, "result.catalog_loaded", __func__);
		expect(result.diagnostics.empty(), "result.diagnostics.empty()", __func__);
		expect(i18n::active_locale() == "ko-KR", "i18n::active_locale() == \"ko-KR\"", __func__);
		expect(i18n::tr("hello", "Hello") == "안녕하세요", "i18n::tr(\"hello\", \"Hello\") == \"안녕하세요\"", __func__);
		expect(i18n::tr("missing", "English fallback") == "English fallback", "missing key uses English fallback", __func__);
		expect(i18n::tr("count", "{total} of {current}") == "{total}개 중 {current}", "matching placeholders use Korean value", __func__);
		expect(i18n::tr("count", "{total} only") == "{total} only", "mismatched placeholders use English fallback", __func__);
		expect(i18n::tr("markup", "<bold color={accent}>Notice</>") == "<bold color={accent}>안내</>", "balanced Nana markup uses Korean value", __func__);
	}

	void test_rejects_bad_catalog_structure_and_utf8()
	{
		i18n::reset_for_tests();
		auto result = i18n::load_catalog(std::filesystem::temp_directory_path() / "missing-i18n-catalog.json");
		expect(!result.catalog_loaded, "missing file rejects catalog", __func__);
		expect(result.diagnostics.size() == 1 && result.diagnostics.front().key == "catalog" && result.diagnostics.front().reason == "file unavailable", "missing file reports sanitized diagnostic", __func__);

		catalog_file bad_root(R"([])", "bad-root");
		result = i18n::load_catalog(bad_root.path);
		expect(!result.catalog_loaded, "!result.catalog_loaded", __func__);
		expect(!result.diagnostics.empty() && result.diagnostics.front().key == "catalog", "sanitized catalog diagnostic key", __func__);
		expect(i18n::active_locale() == "en-US", "i18n::active_locale() == \"en-US\"", __func__);
		expect(i18n::tr("hello", "Hello") == "Hello", "rejected catalog uses English fallback", __func__);

		catalog_file bad_schema(R"({"locale":"ko-KR","schemaVersion":"1","strings":{}})", "bad-schema");
		result = i18n::load_catalog(bad_schema.path);
		expect(!result.catalog_loaded, "schema must be an integer one", __func__);

		catalog_file bad_locale(R"({"locale":"en-US","schemaVersion":1,"strings":{}})", "bad-locale");
		result = i18n::load_catalog(bad_locale.path);
		expect(!result.catalog_loaded, "locale must be ko-KR", __func__);

		catalog_file bad_strings(R"({"locale":"ko-KR","schemaVersion":1,"strings":[]})", "bad-strings");
		result = i18n::load_catalog(bad_strings.path);
		expect(!result.catalog_loaded, "strings must be an object", __func__);

		catalog_file bad_json(R"({"locale":"ko-KR")", "bad-json");
		result = i18n::load_catalog(bad_json.path);
		expect(!result.catalog_loaded, "malformed JSON rejects catalog", __func__);

		std::string invalid_utf8 {R"({"locale":"ko-KR","schemaVersion":1,"strings":{"hello":")"};
		invalid_utf8.push_back(static_cast<char>(0xFF));
		invalid_utf8 += R"("}})";
		catalog_file bad_utf8(invalid_utf8, "bad-utf8");
		result = i18n::load_catalog(bad_utf8.path);
		expect(!result.catalog_loaded, "invalid UTF-8 rejects catalog", __func__);
	}

	void test_rejects_bad_entries_and_reset()
	{
		catalog_file catalog(
			R"({"locale":"ko-KR","schemaVersion":1,"strings":{"valid":"정상","number":3,"empty":"","markup":"<bold>broken","bad\nkey":"잘못된 키"}})",
			"bad-entries"
		);
		i18n::reset_for_tests();
		auto result = i18n::load_catalog(catalog.path);
		expect(result.catalog_loaded, "valid entries load despite rejected entries", __func__);
		expect(result.diagnostics.size() == 4, "each rejected entry reports a diagnostic", __func__);
		bool has_sanitized_key {};
		for(const auto &entry : result.diagnostics)
			has_sanitized_key = has_sanitized_key || entry.key == "invalid-key";
		expect(has_sanitized_key, "entry diagnostic key is sanitized", __func__);
		expect(i18n::tr("valid", "Valid") == "정상", "valid entry remains available", __func__);
		expect(i18n::tr("number", "Number") == "Number", "non-string entry uses English fallback", __func__);
		expect(i18n::tr("empty", "Empty") == "Empty", "empty entry uses English fallback", __func__);
		expect(i18n::tr("markup", "Markup") == "Markup", "malformed markup uses English fallback", __func__);
		i18n::reset_for_tests();
		expect(i18n::active_locale() == "en-US", "reset returns English locale", __func__);
		expect(i18n::tr("valid", "Valid") == "Valid", "reset removes stale translations", __func__);
	}
}

int run_i18n_tests()
{
	test_valid_catalog_and_fallbacks();
	test_rejects_bad_catalog_structure_and_utf8();
	test_rejects_bad_entries_and_reset();
	return failures;
}
