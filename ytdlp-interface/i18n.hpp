#pragma once

#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace i18n
{
	struct diagnostic
	{
		std::string key;
		std::string reason;
	};

	struct load_result
	{
		bool catalog_loaded {};
		std::vector<diagnostic> diagnostics;
	};

	load_result load_catalog(const std::filesystem::path &path);
	std::string tr(std::string_view key, std::string_view english_fallback);
	std::string active_locale();
	void reset_for_tests();
}
