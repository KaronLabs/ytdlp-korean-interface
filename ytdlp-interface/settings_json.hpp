#pragma once

#include <string>
#include <utility>
#include <vector>

#include "json.hpp"
#include "state_tokens.hpp"

struct settings_json_t
{
	using queue_items_t = std::vector<std::pair<std::string, std::vector<std::string>>>;
	using queue_states_t = std::vector<std::vector<queue_item_state>>;

	std::string language {"en-US"};
	queue_items_t unfinished_queue_items;
	queue_states_t unfinished_queue_states;

	void to_json(nlohmann::json &j) const
	{
		auto &jitems {j["unfinished_queue_items"] = nlohmann::json::array()};
		auto &jstates {j["unfinished_queue_states"] = nlohmann::json::array()};
		for(size_t category {0}; category < unfinished_queue_items.size(); category++)
		{
			const auto &items {unfinished_queue_items[category]};
			const auto &states {category < unfinished_queue_states.size() ? unfinished_queue_states[category] : queue_states_t::value_type {}};
			for(size_t item {0}; item < items.second.size(); item++)
				jstates.push_back(queue_item_state_token(item < states.size() ? states[item] : queue_item_state::queued));
			if(items.first.empty())
				for(const auto &url : items.second)
					jitems.push_back(url);
			else if(!items.second.empty())
			{
				jitems.push_back(nlohmann::json::object());
				auto &jcategory {jitems.back()};
				jcategory["name"] = items.first;
				jcategory["items"] = items.second;
			}
		}
		j["language"] = language;
	}

	void from_json(const nlohmann::json &j)
	{
		language = normalized_language(j.contains("language") && j["language"].is_string() ? j["language"].get<std::string>() : "");
		unfinished_queue_items.clear();
		unfinished_queue_states.clear();
		if(!j.contains("unfinished_queue_items") || !j["unfinished_queue_items"].is_array() || j["unfinished_queue_items"].empty())
			return;

		auto &cat0 {unfinished_queue_items.emplace_back("", std::vector<std::string>{}).second};
		unfinished_queue_states.emplace_back();
		for(const auto &entry : j["unfinished_queue_items"])
		{
			if(entry.is_string())
				cat0.push_back(entry.get<std::string>());
			else if(entry.is_object() && entry.contains("name") && entry.contains("items") && entry["name"].is_string() && entry["items"].is_array())
			{
				auto &category {unfinished_queue_items.emplace_back(entry["name"].get<std::string>(), std::vector<std::string>{}).second};
				for(const auto &url : entry["items"])
					if(url.is_string())
						category.push_back(url.get<std::string>());
				unfinished_queue_states.emplace_back();
			}
		}

		const auto states {j.contains("unfinished_queue_states") && j["unfinished_queue_states"].is_array() ? &j["unfinished_queue_states"] : nullptr};
		size_t state_index {};
		for(size_t category {0}; category < unfinished_queue_items.size(); category++)
			for(size_t item {0}; item < unfinished_queue_items[category].second.size(); item++, state_index++)
				unfinished_queue_states[category].push_back(states && state_index < states->size() && (*states)[state_index].is_string() ?
					queue_item_state_from_token((*states)[state_index].get<std::string>()) : queue_item_state::queued);
	}
};
