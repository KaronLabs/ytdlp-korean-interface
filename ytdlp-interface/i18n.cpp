#include "i18n.hpp"

#include "json.hpp"

#include <cctype>
#include <fstream>
#include <iterator>
#include <mutex>
#include <unordered_map>

namespace
{
	struct locale_state
	{
		std::unordered_map<std::string, std::string> strings;
		std::string locale {"en-US"};
	};

	std::mutex state_mutex;
	locale_state state;

	bool is_continuation(unsigned char byte)
	{
		return byte >= 0x80 && byte <= 0xBF;
	}

	bool is_valid_utf8(std::string_view value)
	{
		for(size_t index {}; index < value.size();)
		{
			const auto byte = static_cast<unsigned char>(value[index]);
			if(byte <= 0x7F)
			{
				++index;
				continue;
			}
			const auto has = [&](size_t count)
			{
				return index + count < value.size();
			};
			if(byte >= 0xC2 && byte <= 0xDF && has(1) && is_continuation(static_cast<unsigned char>(value[index + 1])))
			{
				index += 2;
			}
			else if(byte == 0xE0 && has(2) && static_cast<unsigned char>(value[index + 1]) >= 0xA0 && static_cast<unsigned char>(value[index + 1]) <= 0xBF && is_continuation(static_cast<unsigned char>(value[index + 2])))
			{
				index += 3;
			}
			else if(((byte >= 0xE1 && byte <= 0xEC) || (byte >= 0xEE && byte <= 0xEF)) && has(2) && is_continuation(static_cast<unsigned char>(value[index + 1])) && is_continuation(static_cast<unsigned char>(value[index + 2])))
			{
				index += 3;
			}
			else if(byte == 0xED && has(2) && static_cast<unsigned char>(value[index + 1]) >= 0x80 && static_cast<unsigned char>(value[index + 1]) <= 0x9F && is_continuation(static_cast<unsigned char>(value[index + 2])))
			{
				index += 3;
			}
			else if(byte == 0xF0 && has(3) && static_cast<unsigned char>(value[index + 1]) >= 0x90 && static_cast<unsigned char>(value[index + 1]) <= 0xBF && is_continuation(static_cast<unsigned char>(value[index + 2])) && is_continuation(static_cast<unsigned char>(value[index + 3])))
			{
				index += 4;
			}
			else if(byte >= 0xF1 && byte <= 0xF3 && has(3) && is_continuation(static_cast<unsigned char>(value[index + 1])) && is_continuation(static_cast<unsigned char>(value[index + 2])) && is_continuation(static_cast<unsigned char>(value[index + 3])))
			{
				index += 4;
			}
			else if(byte == 0xF4 && has(3) && static_cast<unsigned char>(value[index + 1]) >= 0x80 && static_cast<unsigned char>(value[index + 1]) <= 0x8F && is_continuation(static_cast<unsigned char>(value[index + 2])) && is_continuation(static_cast<unsigned char>(value[index + 3])))
			{
				index += 4;
			}
			else
			{
				return false;
			}
		}
		return true;
	}

	std::string sanitized_key(std::string_view key)
	{
		if(key.empty() || key.size() > 120)
			return "invalid-key";
		for(const auto character : key)
			if(!(std::isalnum(static_cast<unsigned char>(character)) || character == '.' || character == '_' || character == '-'))
				return "invalid-key";
		return std::string(key);
	}

	bool has_valid_nana_markup(std::string_view value)
	{
		std::vector<std::string> open_tags;
		for(size_t index {}; index < value.size(); ++index)
		{
			if(value[index] != '<')
				continue;
			if(value.substr(index, 3) == "</>")
			{
				if(open_tags.empty())
					return false;
				open_tags.pop_back();
				index += 2;
				continue;
			}
			if(index + 1 >= value.size() || !std::isalpha(static_cast<unsigned char>(value[index + 1])))
				return false;
			size_t cursor = index + 1;
			while(cursor < value.size() && (std::isalnum(static_cast<unsigned char>(value[cursor])) || value[cursor] == '_' || value[cursor] == '-'))
				++cursor;
			open_tags.emplace_back(value.substr(index + 1, cursor - index - 1));
			bool quoted {};
			for(; cursor < value.size() && value[cursor] != '>'; ++cursor)
			{
				if(value[cursor] == '"')
					quoted = !quoted;
				else if(value[cursor] == '<' || (!quoted && value[cursor] == '\n'))
					return false;
			}
			if(cursor == value.size() || quoted)
				return false;
			index = cursor;
		}
		return open_tags.empty();
	}

	std::unordered_map<std::string, size_t> placeholders(std::string_view value)
	{
		std::unordered_map<std::string, size_t> result;
		for(size_t index {}; index < value.size(); ++index)
		{
			if(value[index] != '{' || index + 1 == value.size() || !(std::isalpha(static_cast<unsigned char>(value[index + 1])) || value[index + 1] == '_'))
				continue;
			size_t end = index + 2;
			while(end < value.size() && (std::isalnum(static_cast<unsigned char>(value[end])) || value[end] == '_'))
				++end;
			if(end < value.size() && value[end] == '}')
			{
				++result[std::string(value.substr(index, end - index + 1))];
				index = end;
			}
		}
		return result;
	}

	void add_catalog_diagnostic(i18n::load_result &result, std::string_view key, std::string_view reason)
	{
		result.diagnostics.push_back({sanitized_key(key), std::string(reason)});
	}
}

namespace i18n
{
	load_result load_catalog(const std::filesystem::path &path)
	{
		load_result result;
		std::ifstream input(path, std::ios::binary);
		if(!input)
		{
			add_catalog_diagnostic(result, "catalog", "file unavailable");
			reset_for_tests();
			return result;
		}
		const std::string contents {std::istreambuf_iterator<char>(input), {}};
		if(!is_valid_utf8(contents))
		{
			add_catalog_diagnostic(result, "catalog", "invalid UTF-8");
			reset_for_tests();
			return result;
		}

		nlohmann::json catalog;
		try
		{
			catalog = nlohmann::json::parse(contents);
		}
		catch(const nlohmann::json::exception &)
		{
			add_catalog_diagnostic(result, "catalog", "invalid JSON");
			reset_for_tests();
			return result;
		}
		if(!catalog.is_object() || !catalog.contains("schemaVersion") || !catalog.contains("locale") || !catalog.contains("strings"))
		{
			add_catalog_diagnostic(result, "catalog", "invalid root");
			reset_for_tests();
			return result;
		}
		if(!(catalog["schemaVersion"].is_number_integer() || catalog["schemaVersion"].is_number_unsigned()) || catalog["schemaVersion"] != 1)
		{
			add_catalog_diagnostic(result, "catalog", "unsupported schema version");
			reset_for_tests();
			return result;
		}
		if(!catalog["locale"].is_string() || catalog["locale"].get<std::string>() != "ko-KR")
		{
			add_catalog_diagnostic(result, "catalog", "unsupported locale");
			reset_for_tests();
			return result;
		}
		if(!catalog["strings"].is_object())
		{
			add_catalog_diagnostic(result, "catalog", "invalid strings");
			reset_for_tests();
			return result;
		}

		std::unordered_map<std::string, std::string> translations;
		for(auto iterator = catalog["strings"].begin(); iterator != catalog["strings"].end(); ++iterator)
		{
			const auto key = iterator.key();
			if(!iterator.value().is_string())
			{
				add_catalog_diagnostic(result, key, "non-string value");
				continue;
			}
			const auto value = iterator.value().get<std::string>();
			if(value.empty())
			{
				add_catalog_diagnostic(result, key, "empty value");
				continue;
			}
			if(!has_valid_nana_markup(value))
			{
				add_catalog_diagnostic(result, key, "malformed Nana markup");
				continue;
			}
			translations.emplace(key, value);
		}

		{
			std::lock_guard lock(state_mutex);
			state.strings = std::move(translations);
			state.locale = "ko-KR";
		}
		result.catalog_loaded = true;
		return result;
	}

	std::string tr(std::string_view key, std::string_view english_fallback)
	{
		std::lock_guard lock(state_mutex);
		const auto translation = state.strings.find(std::string(key));
		if(translation == state.strings.end() || placeholders(translation->second) != placeholders(english_fallback))
			return std::string(english_fallback);
		return translation->second;
	}

	std::string active_locale()
	{
		std::lock_guard lock(state_mutex);
		return state.locale;
	}

	void reset_for_tests()
	{
		std::lock_guard lock(state_mutex);
		state = {};
	}
}
