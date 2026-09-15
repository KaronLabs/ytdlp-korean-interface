#include "download_policy.hpp"
#include <fstream>
#include <iostream>
#include <functional>

using nlohmann::json;
namespace dp = download_policy;

namespace {
int checks = 0, failures = 0;
void expect(bool condition, const std::string& label)
{
    ++checks;
    if(!condition) { ++failures; std::cerr << "FAIL " << label << '\n'; }
}
json video(int width = 1920, int height = 1080, std::string codec = "h264")
{
    return {{"format_id", "v1080"}, {"vcodec", codec}, {"acodec", "none"},
        {"width", width}, {"height", height}};
}
json audio() { return {{"format_id", "audio"}, {"vcodec", "none"}, {"acodec", "aac"}}; }
json selected(json v = video()) { return {{"requested_formats", json::array({v, audio()})}}; }
json inspected(const dp::inspection& result)
{
    return {{"valid", result.valid}, {"video", result.video}, {"audio", result.audio},
        {"dimensions_known", result.dimensions_known}, {"boundary", result.boundary},
        {"width", result.width}, {"height", result.height},
        {"format_ids", result.format_ids}, {"error", result.error}};
}
bool has(const std::vector<std::string>& args, const std::string& value)
{ return std::find(args.begin(), args.end(), value) != args.end(); }
void reject(const json& metadata, const dp::policy& policy, const std::string& label)
{
    auto result = dp::inspect_selected(metadata, policy);
    expect(!result.valid && !result.error.empty(), label);
}

void test_policy()
{
    dp::policy p;
    expect(p.version == 1 && p.mode_value == dp::mode::basic_video &&
           p.quality_value == dp::quality::p1080, "fresh defaults video 1080");
    for(auto mode : {dp::mode::basic_video, dp::mode::basic_audio, dp::mode::advanced})
        for(auto quality : {dp::quality::p1080, dp::quality::p720, dp::quality::best})
        {
            p.mode_value = mode; p.quality_value = quality;
            auto restored = dp::deserialize(dp::serialize(p));
            expect(restored.version == 1 && restored.mode_value == mode &&
                   restored.quality_value == quality, "policy roundtrip");
        }
    for(const auto& invalid : std::vector<json>{nullptr, json::array(), json::object(), 7, "bad",
        {{"version", 2}, {"mode", "video"}, {"quality", "1080p"}},
        {{"version", "1"}, {"mode", "video"}, {"quality", "1080p"}},
        {{"version", 1}, {"mode", "video"}, {"quality", "2160p"}},
        {{"version", 1}, {"mode", "other"}, {"quality", "1080p"}},
        {{"version", 1}, {"mode", "video"}},
        {{"version", true}, {"mode", "video"}, {"quality", "1080p"}}})
        expect(dp::deserialize(invalid).mode_value == dp::mode::advanced,
               "missing/invalid/legacy policy restores advanced");
    p = {};
    const auto args = dp::arguments(p);
    expect(has(args, "--ignore-config") && has(args, "bv*+ba/b") && has(args, "res:1080"),
           "basic video isolation selector and cap sort");
    expect(!has(args, "-x") && !has(args, "--audio-format") && !has(args, "--recode-video")
           && !has(args, "--remux-video") && !has(args, "--merge-output-format"),
           "video never extracts audio or forces codec/container");
    p.quality_value = dp::quality::p720;
    expect(has(dp::arguments(p), "res:720"), "720 sorting");
    p.quality_value = dp::quality::best;
    expect(dp::resolution_cap(p) == 0 && has(dp::arguments(p), "res"), "best unbounded");
    p.mode_value = dp::mode::basic_audio;
    expect(has(dp::arguments(p), "-x") && has(dp::arguments(p), "mp3"), "MP3 policy preserved");
    p.mode_value = dp::mode::advanced;
    expect(dp::arguments(p).empty(), "advanced adds no basic arguments");
    p = {};
    expect(has(dp::arguments(p, "v1080+audio"), "v1080+audio")
           && !has(dp::arguments(p, "v1080+audio"), "bv*+ba/b"), "pin replaces selector without fallback");
    for(const auto& id : {"best", "b", "ba", "bv", "all", "mergeall", "w", "wa", "wv", "worstvideo", "worstaudio",
                         "best.2", "bv.2", "ba.2", "worst.2", "wv.2", "wa.2", "bestvideo.2", "worstaudio.2",
                         "mp4", "webm", "m4a", "mp3", "v1080+ba", "bv+audio", "v1080/best", "v1080,720",
                         "v1080[height<=1080]", "v1080;echo", "v1080\"", "v1080+", "+audio", "v1080++audio"})
    {
        bool threw = false;
        try { dp::arguments(p, id); } catch(const std::invalid_argument&) { threw = true; }
        expect(threw, std::string("reject nonliteral pin: ") + id);
    }
    for(const auto& id : {"137+140", "v1080+audio", "h264.1+audio.en", "dash-video_1080+audio", "22", "0"})
    {
        bool accepted = false;
        try { accepted = has(dp::arguments(p, id), id); } catch(const std::invalid_argument&) {}
        expect(accepted, std::string("preserve literal format IDs: ") + id);
    }
}

void test_selected()
{
    dp::policy p;
    auto good = dp::inspect_selected(selected(), p);
    expect(good.valid && good.audio && good.video && good.dimensions_known &&
           good.format_ids == "v1080+audio", "separate video/audio selected");
    auto muxed = video(640, 360); muxed["format_id"] = "muxed360"; muxed["acodec"] = "aac";
    expect(dp::inspect_selected(muxed, p).valid, "muxed lower resolution accepted");
    expect(dp::inspect_selected(selected(video(1080, 1920)), p).valid, "portrait uses short edge");
    reject(selected(video(3840, 2160)), p, "above-cap rejected");
    p.quality_value = dp::quality::p720;
    reject(selected(), p, "1080 rejected at 720 cap");
    expect(dp::inspect_selected(selected(video(1280, 720)), p).valid, "exact 720 boundary accepted");
    p = {};
    for(const auto& bad : std::vector<json>{nullptr, "1080", 0, -1, 1080.5, 1e30})
    {
        auto v = video(); v["height"] = bad;
        reject(selected(v), p, "invalid/unknown height rejected in capped mode");
    }
    auto unknown = video(); unknown.erase("width"); unknown.erase("height");
    reject(selected(unknown), p, "unknown dimensions capped rejected");
    p.quality_value = dp::quality::best;
    auto best = dp::inspect_selected(selected(unknown), p);
    expect(best.valid && !best.dimensions_known, "best accepts honest unknown dimensions");
    p = {};
    reject(video(), p, "video-only rejected");
    reject(audio(), p, "audio-only rejected in video mode");
    reject(nullptr, p, "null metadata rejected");
    reject(json::array(), p, "array metadata rejected");
    reject({{"requested_downloads", json::array()}}, p, "zero requested downloads rejected");
    reject({{"requested_downloads", json::array({selected(), selected()})}}, p, "multiple downloads rejected");
    reject({{"requested_formats", json::array()}}, p, "empty selected streams rejected");
    reject({{"requested_formats", json::array({7})}}, p, "malformed selected stream rejected");
    auto wrapper = json{{"requested_downloads", json::array({selected()})}};
    expect(dp::inspect_selected(wrapper, p).valid, "real requested_downloads nesting accepted");
    for(const auto& boundary : std::vector<json>{{{"_type", "playlist"}}, {{"_type", "multi_video"}},
        {{"entries", json::array()}}, {{"is_live", true}}, {{"live_status", "is_live"}},
        {{"live_status", "is_upcoming"}}, {{"live_status", "post_live"}}})
    {
        auto input = selected(); input.update(boundary);
        auto result = dp::inspect_selected(input, p);
        expect(!result.valid && result.boundary, "playlist/live routes to advanced");
    }
    for(const auto& codec : {"vp9", "av1"})
        expect(dp::inspect_selected(selected(video(1920, 1080, codec)), p).valid,
               std::string("accept native codec without downgrade: ") + codec);
    auto changed = dp::inspect_selected(selected(video(1280, 720)), p);
    expect(!dp::same_selection(good, changed), "changed preview resolution suspends");
    expect(!dp::same_selection(good, dp::inspect_selected(video(), p)), "changed/missing audio suspends");
    expect(dp::same_selection(good, dp::inspect_selected(selected(), p)), "stable preview accepted");
    auto different_id = selected(); different_id["requested_formats"][0]["format_id"] = "replacement";
    expect(dp::same_selection(good, dp::inspect_selected(different_id, p)),
           "same media characteristics allow newly resolved literal ID");
    auto multiple = selected(); multiple["requested_formats"].push_back(video(3840, 2160));
    reject(multiple, p, "cannot hide second above-cap video behind valid first stream");
}

void test_output()
{
    dp::policy p;
    json v = {{"codec_type", "video"}, {"codec_name", "vp9"}, {"width", 1920}, {"height", 1080}};
    json a = {{"codec_type", "audio"}, {"codec_name", "aac"}};
    auto output = json{{"streams", json::array({v, a})}};
    expect(dp::inspect_output(output, p).valid, "ffprobe video+audio accepted");
    expect(!dp::inspect_output({{"streams", json::array({v})}}, p).valid, "silent output rejected");
    expect(!dp::inspect_output({{"streams", json::array({a})}}, p).valid, "audio-only output rejected");
    expect(!dp::inspect_output(json::object(), p).valid, "missing probe streams rejected");
    expect(!dp::inspect_output({{"streams", "broken"}}, p).valid, "broken probe structure rejected");
    auto cover = v; cover["disposition"] = {{"attached_pic", 1}};
    expect(!dp::inspect_output({{"streams", json::array({cover, a})}}, p).valid,
           "album cover does not count as video");
    output["streams"][0]["width"] = 3840; output["streams"][0]["height"] = 2160;
    expect(!dp::inspect_output(output, p).valid, "final above-cap file rejected");
    output["streams"][0]["width"] = 1080; output["streams"][0]["height"] = 1920;
    expect(dp::inspect_output(output, p).valid, "final portrait accepted");
    p.mode_value = dp::mode::basic_audio;
    a["codec_name"] = "mp3";
    expect(dp::inspect_output({{"streams", json::array({a})}}, p).valid, "real MP3 output accepted");
    expect(dp::inspect_output({{"streams", json::array({cover, a})}}, p).valid, "MP3 cover art accepted");
    expect(!dp::inspect_output({{"streams", json::array({v, a})}}, p).valid, "MP3 with actual video rejected");
    a["codec_name"] = "aac";
    expect(!dp::inspect_output({{"streams", json::array({a})}}, p).valid, "AAC is not MP3");
}
}

int main(int argc, char** argv)
{
    try
    {
        if(argc == 3 && std::string(argv[1]) == "--request")
        {
            std::ifstream input(argv[2]);
            const auto request = json::parse(input);
            const auto p = request.contains("policy") ? dp::deserialize(request["policy"]) : dp::policy{};
            const auto op = request.at("operation").get<std::string>();
            json result;
            if(op == "arguments") result = dp::arguments(p, request.value("pinned_ids", std::string{}));
            else if(op == "selected") result = inspected(dp::inspect_selected(request.at("metadata"), p));
            else if(op == "output") result = inspected(dp::inspect_output(request.at("metadata"), p));
            else if(op == "same") result = dp::same_selection(dp::inspect_selected(request.at("before"), p),
                                                              dp::inspect_selected(request.at("after"), p));
            else throw std::invalid_argument("unknown_operation");
            std::cout << result.dump() << '\n';
            return 0;
        }
        if(argc != 1) throw std::invalid_argument("usage: quality_policy_tests [--request input.json]");
        test_policy(); test_selected(); test_output();
        std::cout << "production_helper_checks=" << checks << " failures=" << failures << '\n';
        return failures ? 1 : 0;
    }
    catch(const std::exception& error) { std::cerr << error.what() << '\n'; return 2; }
}
