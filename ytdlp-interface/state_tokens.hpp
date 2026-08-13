#pragma once

#include <string_view>

enum class queue_item_state
{
	queued,
	active,
	stopped,
	done,
	error,
	skipped,
};

inline constexpr std::string_view normalized_language(std::string_view language)
{
	return language == "ko-KR" ? language : "en-US";
}

inline constexpr std::string_view queue_item_state_token(queue_item_state state)
{
	switch(state)
	{
	case queue_item_state::active: return "active";
	case queue_item_state::stopped: return "stopped";
	case queue_item_state::done: return "done";
	case queue_item_state::error: return "error";
	case queue_item_state::skipped: return "skipped";
	default: return "queued";
	}
}

inline constexpr queue_item_state queue_item_state_from_token(std::string_view token)
{
	if(token == "active") return queue_item_state::active;
	if(token == "stopped") return queue_item_state::stopped;
	if(token == "done") return queue_item_state::done;
	if(token == "error") return queue_item_state::error;
	if(token == "skipped") return queue_item_state::skipped;
	return queue_item_state::queued;
}

inline constexpr queue_item_state queue_item_state_from_legacy_status(std::string_view status)
{
	if(status == "started" || status == "downloading" || status == "processing") return queue_item_state::active;
	if(status == "done") return queue_item_state::done;
	if(status == "error") return queue_item_state::error;
	if(status == "skip" || status == "skipped") return queue_item_state::skipped;
	if(status.starts_with("stopped")) return queue_item_state::stopped;
	return queue_item_state::queued;
}
