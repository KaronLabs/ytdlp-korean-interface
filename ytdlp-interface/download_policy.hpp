#pragma once

#include "json.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

// Production policy shared by the GUI and independent, platform-free tests.
namespace download_policy
{
enum class mode { basic_video, basic_audio, advanced };
enum class quality { p1080, p720, best };

struct policy
{
    int version = 1;
    mode mode_value = mode::basic_video;
    quality quality_value = quality::p1080;
};

struct inspection
{
    bool valid = false, video = false, audio = false;
    bool dimensions_known = false, boundary = false;
    int width = 0, height = 0;
    std::string format_ids, error;
};

inline bool is_basic(const policy& p) { return p.mode_value != mode::advanced; }
inline int resolution_cap(const policy& p)
{
    if(p.mode_value != mode::basic_video || p.quality_value == quality::best) return 0;
    return p.quality_value == quality::p720 ? 720 : 1080;
}

inline nlohmann::json serialize(const policy& p)
{
    return {{"version", p.version},
        {"mode", p.mode_value == mode::basic_video ? "video" : p.mode_value == mode::basic_audio ? "audio" : "advanced"},
        {"quality", p.quality_value == quality::p720 ? "720p" : p.quality_value == quality::best ? "best" : "1080p"}};
}

inline policy deserialize(const nlohmann::json& j)
{
    policy p;
    p.mode_value = mode::advanced;
    if(!j.is_object() || !j.contains("version") || !j["version"].is_number_integer() || j["version"] != 1 ||
        !j.contains("mode") || !j["mode"].is_string() || !j.contains("quality") || !j["quality"].is_string()) return p;
    const auto m = j["mode"].get<std::string>(), q = j["quality"].get<std::string>();
    if((m != "video" && m != "audio" && m != "advanced") || (q != "1080p" && q != "720p" && q != "best")) return p;
    p.mode_value = m == "video" ? mode::basic_video : m == "audio" ? mode::basic_audio : mode::advanced;
    p.quality_value = q == "720p" ? quality::p720 : q == "best" ? quality::best : quality::p1080;
    return p;
}

namespace detail
{
inline std::string string(const nlohmann::json& j, const char* key)
{
    const auto it = j.find(key);
    return it != j.end() && it->is_string() ? it->get<std::string>() : "";
}
inline int dimension(const nlohmann::json& j, const char* key)
{
    const auto it = j.find(key);
    if(it == j.end() || !it->is_number()) return 0;
    const auto n = it->get<double>();
    return std::isfinite(n) && n > 0 && n <= (std::numeric_limits<int>::max)() && std::floor(n) == n ? static_cast<int>(n) : 0;
}
inline bool codec(const nlohmann::json& j, const char* key)
{
    const auto s = string(j, key);
    return !s.empty() && s != "none" && s != "unknown";
}
inline bool literal_id(const std::string& s)
{
    if(s.empty() || s == "-" || s == "all" || s == "mergeall") return false;
    // These names select by extension instead of matching an exact format ID.
    for(const auto* extension : {"3gp", "aac", "avi", "flv", "mkv", "mov", "mp4", "webm",
        "aiff", "alac", "flac", "m4a", "mka", "mp3", "ogg", "opus", "wav", "mhtml"})
        if(s == extension) return false;
    // yt-dlp also interprets positive .N suffixes and short/long type aliases.
    // Starred variants are already rejected by the character allowlist below.
    const auto dot = s.find('.');
    const auto name = s.substr(0, dot);
    if(dot == std::string::npos || (dot + 1 < s.size() && s[dot + 1] >= '1' && s[dot + 1] <= '9' &&
        s.find_first_not_of("0123456789", dot + 1) == std::string::npos))
        for(const auto* selector : {"best", "b", "worst", "w",
            "bestvideo", "bestv", "bvideo", "bv", "bestaudio", "besta", "baudio", "ba",
            "worstvideo", "worstv", "wvideo", "wv", "worstaudio", "worsta", "waudio", "wa"})
            if(name == selector) return false;
    return std::all_of(s.begin(), s.end(), [](unsigned char c) {
        return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c == '-' || c == '.';
    });
}
inline bool pinned(const std::string& ids)
{
    size_t begin = 0;
    for(;;)
    {
        const auto end = ids.find('+', begin);
        if(!literal_id(ids.substr(begin, end == std::string::npos ? end : end - begin))) return false;
        if(end == std::string::npos) return true;
        begin = end + 1;
    }
}
inline bool boundary(const nlohmann::json& j)
{
    const auto type = string(j, "_type"), live = string(j, "live_status");
    return type == "playlist" || type == "multi_video" || j.contains("entries") ||
        (j.contains("is_live") && j["is_live"] == true) || live == "is_live" || live == "is_upcoming" || live == "post_live";
}
inline void finish(inspection& r, const policy& p, bool output)
{
    if(!r.error.empty()) return;
    if(!r.audio) r.error = "missing_audio";
    else if(p.mode_value == mode::basic_video && !r.video) r.error = "missing_video";
    else if(resolution_cap(p) && !r.dimensions_known) r.error = "unknown_dimensions";
    else if(resolution_cap(p) && (std::min)(r.width, r.height) > resolution_cap(p)) r.error = "resolution_exceeds_cap";
    else if(output && p.mode_value == mode::basic_audio && r.video) r.error = "unexpected_video";
    else r.valid = true;
}
}

inline std::vector<std::string> arguments(const policy& p, const std::string& pinned_ids = "")
{
    if(!is_basic(p)) return {};
    if(p.version != 1) throw std::invalid_argument("unsupported_policy");
    if(!pinned_ids.empty() && !detail::pinned(pinned_ids)) throw std::invalid_argument("invalid_format_id");
    std::vector<std::string> args {"--ignore-config", "--no-playlist", "-f",
        pinned_ids.empty() ? (p.mode_value == mode::basic_audio ? "ba/b" : "bv*+ba/b") : pinned_ids};
    if(p.mode_value == mode::basic_audio)
        args.insert(args.end(), {"-x", "--audio-format", "mp3", "--audio-quality", "0"});
    else
    {
        // Resolution leads sorting, including when an extractor supplies codec-first defaults.
        args.insert(args.end(), {"--format-sort-force", "-S", resolution_cap(p) ? "res:" + std::to_string(resolution_cap(p)) : "res"});
    }
    return args;
}

inline inspection inspect_selected(const nlohmann::json& metadata, const policy& p)
{
    inspection r;
    if(!metadata.is_object()) { r.error = "invalid_metadata"; return r; }
    if(detail::boundary(metadata)) { r.boundary = true; r.error = "advanced_required"; return r; }
    const nlohmann::json* selected = &metadata;
    if(metadata.contains("requested_downloads"))
    {
        const auto& downloads = metadata["requested_downloads"];
        if(!downloads.is_array() || downloads.size() != 1 || !downloads[0].is_object())
        { r.error = "invalid_selection"; return r; }
        selected = &downloads[0];
    }
    if(detail::boundary(*selected)) { r.boundary = true; r.error = "advanced_required"; return r; }
    std::vector<const nlohmann::json*> streams;
    if(selected->contains("requested_formats"))
    {
        const auto& formats = (*selected)["requested_formats"];
        if(!formats.is_array() || formats.empty()) { r.error = "invalid_selection"; return r; }
        for(const auto& stream : formats) streams.push_back(&stream);
    }
    else streams.push_back(selected);
    bool unknown_video = false;
    for(const auto* stream : streams)
    {
        if(!stream->is_object()) { r.error = "invalid_selection"; return r; }
        const auto id = detail::string(*stream, "format_id");
        if(!detail::literal_id(id)) { r.error = "invalid_format_id"; return r; }
        if(!r.format_ids.empty()) r.format_ids += '+';
        r.format_ids += id;
        r.audio = r.audio || detail::codec(*stream, "acodec");
        if(detail::codec(*stream, "vcodec"))
        {
            r.video = true;
            const auto w = detail::dimension(*stream, "width"), h = detail::dimension(*stream, "height");
            if(!w || !h) unknown_video = true;
            if(resolution_cap(p) && w && h && (std::min)(w, h) > resolution_cap(p)) r.error = "resolution_exceeds_cap";
            if(!r.width || (std::min)(w, h) > (std::min)(r.width, r.height)) { r.width = w; r.height = h; }
        }
    }
    r.dimensions_known = r.video && r.width > 0 && r.height > 0 && !unknown_video;
    detail::finish(r, p, false);
    return r;
}

inline inspection inspect_output(const nlohmann::json& metadata, const policy& p)
{
    inspection r;
    if(!metadata.is_object() || !metadata.contains("streams") || !metadata["streams"].is_array())
    { r.error = "invalid_output_metadata"; return r; }
    bool unknown_video = false;
    for(const auto& stream : metadata["streams"])
    {
        if(!stream.is_object()) { r.error = "invalid_output_metadata"; return r; }
        const auto type = detail::string(stream, "codec_type");
        if(type == "audio" && detail::codec(stream, "codec_name"))
        {
            r.audio = true;
            if(p.mode_value == mode::basic_audio && detail::string(stream, "codec_name") != "mp3") r.error = "unexpected_audio_codec";
        }
        if(type != "video") continue;
        if(stream.contains("disposition") && stream["disposition"].is_object() &&
            stream["disposition"].contains("attached_pic") && stream["disposition"]["attached_pic"] == 1) continue;
        if(!detail::codec(stream, "codec_name")) continue;
        r.video = true;
        const auto w = detail::dimension(stream, "width"), h = detail::dimension(stream, "height");
        if(!w || !h) unknown_video = true;
        if(resolution_cap(p) && w && h && (std::min)(w, h) > resolution_cap(p)) r.error = "resolution_exceeds_cap";
        if(!r.width || (std::min)(w, h) > (std::min)(r.width, r.height)) { r.width = w; r.height = h; }
    }
    r.dimensions_known = r.video && r.width > 0 && r.height > 0 && !unknown_video;
    detail::finish(r, p, true);
    return r;
}

inline bool same_selection(const inspection& a, const inspection& b)
{
    return a.valid && b.valid && a.video == b.video && a.audio == b.audio &&
        a.dimensions_known == b.dimensions_known && a.width == b.width && a.height == b.height;
}
}
