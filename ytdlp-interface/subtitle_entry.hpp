#pragma once

#include "json.hpp"

#include <string>
#include <string_view>

inline bool subtitle_entry_available(const nlohmann::json &formats)
{
	if(!formats.is_array() || formats.empty() || !formats.front().is_object())
		return false;
	const auto &format {formats.front()};
	for(const auto *field : {"url", "data"})
		if(format.contains(field) && format[field].is_string() && !format[field].get_ref<const std::string&>().empty())
			return true;
	return false;
}

inline std::string subtitle_display_name(std::string_view language, const nlohmann::json &formats)
{
	const auto &format {formats.front()};
	if(format.contains("name") && format["name"].is_string() && !format["name"].get_ref<const std::string&>().empty())
		return format["name"].get<std::string>();
	return std::string {language};
}
